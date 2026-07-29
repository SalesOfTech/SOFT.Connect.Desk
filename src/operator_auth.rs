use hbb_common::{
    anyhow::{anyhow, bail, Context, Result},
    base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _},
    lazy_static::lazy_static,
    rand::{rngs::OsRng, RngCore},
};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use reqwest::blocking::{Client, Response};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    io::{Read, Write},
    net::{IpAddr, TcpListener, TcpStream},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use url::Url;

const ISSUER: &str = "https://connect.salesof.tech";
const DISCOVERY_URL: &str = "https://connect.salesof.tech/.well-known/openid-configuration";
const AUTHORIZE_URL: &str = "https://connect.salesof.tech/oauth/authorize";
const TOKEN_URL: &str = "https://connect.salesof.tech/oauth/token";
const JWKS_URL: &str = "https://connect.salesof.tech/.well-known/jwks.json";
const ME_URL: &str = "https://connect.salesof.tech/oauth/me";
const REVOKE_URL: &str = "https://connect.salesof.tech/oauth/revoke";
const CLIENT_ID: &str = "soft-connect-desk-operator";
const AUDIENCE: &str = "soft-connect-desk";
const REQUIRED_PERMISSION: &str = "soft_connect_desk_operator";
const SCOPES: &str = "openid profile email offline_access soft_connect_desk_operator";
const KEYRING_SERVICE: &str = "tech.salesof.soft-connect-desk.oauth";
const CALLBACK_PATH: &str = "/oauth/callback";
const CALLBACK_TIMEOUT: Duration = Duration::from_secs(300);
const HTTP_TIMEOUT: Duration = Duration::from_secs(20);
const CLOCK_SKEW_SECONDS: u64 = 60;

const ACCESS_TOKEN_ENTRY: &str = "operator-access-token";
const ID_TOKEN_ENTRY: &str = "operator-id-token";
const REFRESH_TOKEN_ENTRY: &str = "operator-refresh-token";
const SESSION_ENTRY: &str = "operator-session";

lazy_static! {
    static ref STATE: Mutex<AuthState> = Mutex::new(AuthState::default());
    static ref OPERATION_RUNNING: AtomicBool = AtomicBool::new(false);
    static ref CANCEL_LOGIN: AtomicBool = AtomicBool::new(false);
}

#[derive(Clone, Default, Deserialize, Serialize)]
struct OperatorProfile {
    sub: String,
    email: String,
    name: String,
}

#[derive(Clone, Serialize)]
struct AuthState {
    status: &'static str,
    message: String,
    profile: Option<OperatorProfile>,
    expires_at: u64,
    initialized: bool,
}

impl Default for AuthState {
    fn default() -> Self {
        Self {
            status: "checking",
            message: String::new(),
            profile: None,
            expires_at: 0,
            initialized: false,
        }
    }
}

#[derive(Clone, Deserialize, Serialize)]
struct StoredSession {
    expires_at: u64,
    scope: String,
    profile: OperatorProfile,
}

#[derive(Deserialize)]
struct DiscoveryDocument {
    issuer: String,
    authorization_endpoint: String,
    token_endpoint: String,
    jwks_uri: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    token_type: String,
    access_token: String,
    refresh_token: Option<String>,
    id_token: Option<String>,
    expires_in: u64,
    #[serde(default)]
    scope: String,
}

#[derive(Clone, Deserialize)]
struct JwtClaims {
    iss: String,
    sub: String,
    aud: Value,
    exp: u64,
    nbf: u64,
    iat: u64,
    #[serde(default)]
    active: bool,
    #[serde(default)]
    permissions: Vec<String>,
    nonce: Option<String>,
    email: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct Jwks {
    keys: Vec<Jwk>,
}

#[derive(Deserialize)]
struct Jwk {
    kty: String,
    kid: String,
    #[serde(default)]
    alg: String,
    #[serde(rename = "use", default)]
    key_use: String,
    n: String,
    e: String,
}

struct VerifiedSession {
    access_token: String,
    id_token: String,
    refresh_token: String,
    expires_at: u64,
    scope: String,
    profile: OperatorProfile,
}

struct LoginAttempt {
    listener: TcpListener,
    redirect_uri: String,
    state: String,
    nonce: String,
    code_verifier: String,
    authorize_url: String,
}

pub fn status_json() -> String {
    ensure_initialized();
    let state = lock_state().clone();
    serde_json::to_string(&state).unwrap_or_else(|_| {
        r#"{"status":"error","message":"Failed to serialize authorization state"}"#.to_owned()
    })
}

pub fn is_authorized() -> bool {
    ensure_initialized();
    let state = lock_state();
    state.status == "authorized" && state.expires_at > now_unix()
}

pub fn connection_allowed() -> bool {
    if is_authorized() {
        return true;
    }
    read_stored_session()
        .map(|session| {
            session
                .map(|session| session.expires_at > now_unix())
                .unwrap_or(false)
        })
        .unwrap_or(false)
}

pub fn start_login() {
    if OPERATION_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    CANCEL_LOGIN.store(false, Ordering::Release);
    set_state("authenticating", "", None, 0, true);
    std::thread::spawn(|| {
        let result = login_flow();
        OPERATION_RUNNING.store(false, Ordering::Release);
        match result {
            Ok(session) => {
                let profile = session.profile.clone();
                let expires_at = session.expires_at;
                if let Err(err) = store_session(&session) {
                    set_error(format!("Не удалось сохранить защищённую сессию: {err}"));
                    return;
                }
                set_state("authorized", "", Some(profile), expires_at, true);
            }
            Err(err) => set_error(user_facing_error(&err)),
        }
    });
}

pub fn cancel_login() {
    CANCEL_LOGIN.store(true, Ordering::Release);
}

pub fn logout() {
    if OPERATION_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    set_state("signing_out", "", None, 0, true);
    std::thread::spawn(|| {
        let refresh_token = read_secret(REFRESH_TOKEN_ENTRY).ok();
        let revoke_result = refresh_token
            .as_deref()
            .map(revoke_refresh_token)
            .transpose();
        let delete_result = delete_session();
        OPERATION_RUNNING.store(false, Ordering::Release);
        if let Err(err) = delete_result {
            set_error(format!(
                "Не удалось удалить локальные токены из защищённого хранилища: {err}"
            ));
            return;
        }
        let message = revoke_result
            .err()
            .map(|err| format!("Локальная сессия завершена. Серверный отзыв не подтверждён: {err}"))
            .unwrap_or_default();
        set_state("unauthenticated", &message, None, 0, true);
    });
}

fn ensure_initialized() {
    {
        let mut state = lock_state();
        if state.initialized {
            if state.status == "authorized"
                && state.expires_at <= now_unix().saturating_add(CLOCK_SKEW_SECONDS)
            {
                drop(state);
                start_refresh();
            }
            return;
        }
        state.initialized = true;
    }
    if OPERATION_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    std::thread::spawn(|| {
        let result = restore_or_refresh_session();
        OPERATION_RUNNING.store(false, Ordering::Release);
        match result {
            Ok(Some(session)) => set_state(
                "authorized",
                "",
                Some(session.profile),
                session.expires_at,
                true,
            ),
            Ok(None) => set_state("unauthenticated", "", None, 0, true),
            Err(err) => {
                let _ = delete_session();
                set_error(user_facing_error(&err));
            }
        }
    });
}

fn start_refresh() {
    if OPERATION_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    std::thread::spawn(|| {
        let result = refresh_stored_session();
        OPERATION_RUNNING.store(false, Ordering::Release);
        match result {
            Ok(session) => set_state(
                "authorized",
                "",
                Some(session.profile),
                session.expires_at,
                true,
            ),
            Err(err) => {
                let _ = delete_session();
                set_error(format!(
                    "Срок сессии истёк. Войдите снова. {}",
                    user_facing_error(&err)
                ));
            }
        }
    });
}

fn restore_or_refresh_session() -> Result<Option<StoredSession>> {
    let stored = match read_stored_session()? {
        Some(value) => value,
        None => {
            delete_session()?;
            return Ok(None);
        }
    };
    let access_token = read_secret(ACCESS_TOKEN_ENTRY)?;
    let id_token = read_secret(ID_TOKEN_ENTRY)?;
    let refresh_token = read_secret(REFRESH_TOKEN_ENTRY)?;

    if stored.expires_at <= now_unix().saturating_add(CLOCK_SKEW_SECONDS) {
        return refresh_tokens(&refresh_token, Some(&id_token)).and_then(|session| {
            store_session(&session)?;
            Ok(Some(StoredSession {
                expires_at: session.expires_at,
                scope: session.scope,
                profile: session.profile,
            }))
        });
    }

    let client = http_client()?;
    let jwks = fetch_jwks(&client)?;
    let access_claims = verify_access_token(&access_token, &jwks)?;
    verify_id_token(&id_token, &jwks, None)?;
    let profile = verify_me(&client, &access_token, &access_claims)?;
    let verified = StoredSession {
        expires_at: stored.expires_at,
        scope: stored.scope,
        profile,
    };
    let _ = refresh_token;
    Ok(Some(verified))
}

fn refresh_stored_session() -> Result<StoredSession> {
    let refresh_token = read_secret(REFRESH_TOKEN_ENTRY)?;
    let id_token = read_secret(ID_TOKEN_ENTRY).ok();
    let session = refresh_tokens(&refresh_token, id_token.as_deref())?;
    store_session(&session)?;
    Ok(StoredSession {
        expires_at: session.expires_at,
        scope: session.scope,
        profile: session.profile,
    })
}

fn login_flow() -> Result<VerifiedSession> {
    let attempt = prepare_login_attempt()?;
    emit_event(json!({
        "name": "operator-auth-browser",
        "url": attempt.authorize_url,
    }));
    let code = wait_for_callback(&attempt.listener, &attempt.state)?;
    exchange_authorization_code(
        &code,
        &attempt.redirect_uri,
        &attempt.code_verifier,
        &attempt.nonce,
    )
}

fn prepare_login_attempt() -> Result<LoginAttempt> {
    let client = http_client()?;
    verify_discovery(&client)?;
    let listener = bind_callback_listener()?;
    let port = listener.local_addr()?.port();
    let redirect_uri = format!("http://127.0.0.1:{port}{CALLBACK_PATH}");
    let state = random_base64url_32();
    let nonce = random_base64url_32();
    let code_verifier = random_base64url_32();
    let code_challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(code_verifier.as_bytes()));

    let mut authorize_url = Url::parse(AUTHORIZE_URL)?;
    authorize_url
        .query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("client_id", CLIENT_ID)
        .append_pair("redirect_uri", &redirect_uri)
        .append_pair("scope", SCOPES)
        .append_pair("state", &state)
        .append_pair("nonce", &nonce)
        .append_pair("code_challenge", &code_challenge)
        .append_pair("code_challenge_method", "S256");

    Ok(LoginAttempt {
        listener,
        redirect_uri,
        state,
        nonce,
        code_verifier,
        authorize_url: authorize_url.to_string(),
    })
}

fn bind_callback_listener() -> Result<TcpListener> {
    for _ in 0..8 {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .context("не удалось запустить локальный OAuth callback listener")?;
        let port = listener.local_addr()?.port();
        if (1024..=65535).contains(&port) {
            listener.set_nonblocking(true)?;
            return Ok(listener);
        }
    }
    bail!("операционная система не выделила допустимый callback-порт");
}

fn wait_for_callback(listener: &TcpListener, expected_state: &str) -> Result<String> {
    let deadline = Instant::now() + CALLBACK_TIMEOUT;
    while Instant::now() < deadline {
        if CANCEL_LOGIN.load(Ordering::Acquire) {
            bail!("вход отменён");
        }
        match listener.accept() {
            Ok((mut stream, peer)) => {
                if !matches!(peer.ip(), IpAddr::V4(ip) if ip.is_loopback()) {
                    continue;
                }
                match parse_callback(&mut stream, expected_state) {
                    Ok(code) => {
                        write_callback_response(&mut stream, true)?;
                        return Ok(code);
                    }
                    Err(err) => {
                        let _ = write_callback_response(&mut stream, false);
                        return Err(err);
                    }
                }
            }
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(err) => return Err(err.into()),
        }
    }
    bail!("время ожидания входа истекло");
}

fn parse_callback(stream: &mut TcpStream, expected_state: &str) -> Result<String> {
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let mut request = Vec::with_capacity(2048);
    let mut chunk = [0_u8; 1024];
    loop {
        let read = stream.read(&mut chunk)?;
        if read == 0 {
            break;
        }
        request.extend_from_slice(&chunk[..read]);
        if request.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
        if request.len() > 16 * 1024 {
            bail!("OAuth callback request is too large");
        }
    }
    let request = std::str::from_utf8(&request)?;
    let request_line = request.lines().next().context("пустой OAuth callback")?;
    let mut parts = request_line.split_whitespace();
    if parts.next() != Some("GET") {
        bail!("OAuth callback использует недопустимый HTTP-метод");
    }
    let target = parts.next().context("OAuth callback не содержит URL")?;
    let callback = Url::parse(&format!("http://127.0.0.1{target}"))?;
    if callback.path() != CALLBACK_PATH {
        bail!("OAuth callback пришёл на неожиданный путь");
    }
    let query: HashMap<String, String> = callback.query_pairs().into_owned().collect();
    if let Some(error) = query.get("error") {
        let description = query
            .get("error_description")
            .map(String::as_str)
            .unwrap_or(error);
        bail!("SOFT.Connect отклонил вход: {description}");
    }
    let returned_state = query
        .get("state")
        .context("OAuth callback не содержит state")?;
    if returned_state.len() != expected_state.len()
        || !hbb_common::sodiumoxide::utils::memcmp(
            returned_state.as_bytes(),
            expected_state.as_bytes(),
        )
    {
        bail!("OAuth state не совпал; вход отменён");
    }
    query
        .get("code")
        .filter(|code| !code.is_empty())
        .cloned()
        .context("OAuth callback не содержит одноразовый code")
}

fn write_callback_response(stream: &mut TcpStream, success: bool) -> Result<()> {
    let (title, message) = if success {
        (
            "SOFT.Connect.Desk",
            "Вход завершён. Можно закрыть эту вкладку и вернуться в приложение.",
        )
    } else {
        (
            "SOFT.Connect.Desk",
            "Вход не завершён. Вернитесь в приложение и повторите попытку.",
        )
    };
    let body = format!(
        "<!doctype html><html lang=\"ru\"><meta charset=\"utf-8\"><title>{title}</title>\
         <body style=\"font-family:system-ui;background:#071426;color:#fff;display:grid;\
         place-items:center;min-height:100vh;margin:0\"><main><h1>{title}</h1><p>{message}</p>\
         </main></body></html>"
    );
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\
         Cache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\n\
         X-Content-Type-Options: nosniff\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(response.as_bytes())?;
    stream.flush()?;
    Ok(())
}

fn exchange_authorization_code(
    code: &str,
    redirect_uri: &str,
    code_verifier: &str,
    nonce: &str,
) -> Result<VerifiedSession> {
    let client = http_client()?;
    let form = [
        ("grant_type", "authorization_code"),
        ("client_id", CLIENT_ID),
        ("code", code),
        ("redirect_uri", redirect_uri),
        ("code_verifier", code_verifier),
    ];
    let tokens: TokenResponse = checked_json(
        client
            .post(TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .form(&form)
            .send()?,
        "получение токенов",
    )?;
    build_verified_session(&client, tokens, None, Some(nonce))
}

fn refresh_tokens(refresh_token: &str, current_id_token: Option<&str>) -> Result<VerifiedSession> {
    let client = http_client()?;
    let form = [
        ("grant_type", "refresh_token"),
        ("client_id", CLIENT_ID),
        ("refresh_token", refresh_token),
    ];
    let tokens: TokenResponse = checked_json(
        client
            .post(TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .form(&form)
            .send()?,
        "обновление токена",
    )?;
    build_verified_session(&client, tokens, current_id_token, None)
}

fn build_verified_session(
    client: &Client,
    tokens: TokenResponse,
    current_id_token: Option<&str>,
    expected_nonce: Option<&str>,
) -> Result<VerifiedSession> {
    if !tokens.token_type.eq_ignore_ascii_case("Bearer") {
        bail!("SOFT.Connect вернул неподдерживаемый тип токена");
    }
    let refresh_token = tokens
        .refresh_token
        .filter(|token| !token.is_empty())
        .context("SOFT.Connect не вернул новый refresh token")?;
    let id_token = tokens
        .id_token
        .filter(|token| !token.is_empty())
        .or_else(|| current_id_token.map(ToOwned::to_owned))
        .context("SOFT.Connect не вернул ID token")?;
    let jwks = fetch_jwks(client)?;
    let access_claims = verify_access_token(&tokens.access_token, &jwks)?;
    let id_claims = verify_id_token(&id_token, &jwks, expected_nonce)?;
    if access_claims.sub != id_claims.sub {
        bail!("subject access token и ID token не совпадает");
    }
    let profile = verify_me(client, &tokens.access_token, &access_claims)?;
    let scope = if tokens.scope.is_empty() {
        SCOPES.to_owned()
    } else {
        tokens.scope
    };
    if !scope
        .split_whitespace()
        .any(|scope| scope == REQUIRED_PERMISSION)
    {
        bail!("access_denied: в токене отсутствует scope {REQUIRED_PERMISSION}");
    }
    Ok(VerifiedSession {
        access_token: tokens.access_token,
        id_token,
        refresh_token,
        expires_at: now_unix().saturating_add(tokens.expires_in),
        scope,
        profile,
    })
}

fn verify_access_token(token: &str, jwks: &Jwks) -> Result<JwtClaims> {
    let claims = verify_jwt(token, jwks)?;
    if !claims.active {
        bail!("access_denied: учётная запись неактивна");
    }
    if !claims
        .permissions
        .iter()
        .any(|permission| permission == REQUIRED_PERMISSION)
    {
        bail!("access_denied: нет разрешения {REQUIRED_PERMISSION}");
    }
    Ok(claims)
}

fn verify_id_token(token: &str, jwks: &Jwks, expected_nonce: Option<&str>) -> Result<JwtClaims> {
    let claims = verify_jwt(token, jwks)?;
    if !claims.active
        || !claims
            .permissions
            .iter()
            .any(|permission| permission == REQUIRED_PERMISSION)
    {
        bail!("access_denied: ID token не подтверждает доступ Operator");
    }
    if let Some(expected_nonce) = expected_nonce {
        let nonce = claims
            .nonce
            .as_deref()
            .context("ID token не содержит nonce")?;
        if nonce.len() != expected_nonce.len()
            || !hbb_common::sodiumoxide::utils::memcmp(nonce.as_bytes(), expected_nonce.as_bytes())
        {
            bail!("nonce ID token не совпал; вход отменён");
        }
    }
    Ok(claims)
}

fn verify_jwt(token: &str, jwks: &Jwks) -> Result<JwtClaims> {
    let header = decode_header(token)?;
    if header.alg != Algorithm::RS256 {
        bail!("JWT использует алгоритм, отличный от RS256");
    }
    let kid = header.kid.context("JWT не содержит kid")?;
    let jwk = jwks
        .keys
        .iter()
        .find(|key| {
            key.kid == kid
                && key.kty == "RSA"
                && (key.alg.is_empty() || key.alg == "RS256")
                && (key.key_use.is_empty() || key.key_use == "sig")
        })
        .context("подходящий RS256 signing key не найден в JWKS")?;
    let key = DecodingKey::from_rsa_components(&jwk.n, &jwk.e)?;
    let mut validation = Validation::new(Algorithm::RS256);
    validation.leeway = CLOCK_SKEW_SECONDS;
    validation.validate_nbf = true;
    validation.set_audience(&[AUDIENCE]);
    validation.set_issuer(&[ISSUER]);
    validation.set_required_spec_claims(&["exp", "nbf", "iss", "aud", "sub"]);
    let claims = decode::<JwtClaims>(token, &key, &validation)?.claims;
    let now = now_unix();
    if claims.iat == 0 || claims.iat > now.saturating_add(CLOCK_SKEW_SECONDS) {
        bail!("JWT содержит недопустимый iat");
    }
    if claims.iss != ISSUER || !audience_contains(&claims.aud, AUDIENCE) {
        bail!("JWT содержит недопустимые issuer или audience");
    }
    if claims.exp <= now.saturating_sub(CLOCK_SKEW_SECONDS)
        || claims.nbf > now.saturating_add(CLOCK_SKEW_SECONDS)
    {
        bail!("JWT ещё не действует или уже истёк");
    }
    Ok(claims)
}

fn audience_contains(audience: &Value, expected: &str) -> bool {
    match audience {
        Value::String(value) => value == expected,
        Value::Array(values) => values.iter().any(|value| value.as_str() == Some(expected)),
        _ => false,
    }
}

fn verify_me(client: &Client, access_token: &str, claims: &JwtClaims) -> Result<OperatorProfile> {
    let me: Value = checked_json(
        client.get(ME_URL).bearer_auth(access_token).send()?,
        "проверка профиля",
    )?;
    if me.get("active").and_then(Value::as_bool) != Some(true) {
        bail!("access_denied: сервер подтвердил неактивную учётную запись");
    }
    let permissions = me
        .get("permissions")
        .and_then(Value::as_array)
        .context("ответ /oauth/me не содержит permissions")?;
    if !permissions
        .iter()
        .any(|permission| permission.as_str() == Some(REQUIRED_PERMISSION))
    {
        bail!("access_denied: сервер не подтвердил разрешение {REQUIRED_PERMISSION}");
    }
    let me_sub = me.get("sub").and_then(Value::as_str).unwrap_or(&claims.sub);
    if me_sub != claims.sub {
        bail!("subject ответа /oauth/me не совпадает с JWT");
    }
    Ok(OperatorProfile {
        sub: claims.sub.clone(),
        email: me
            .get("email")
            .and_then(Value::as_str)
            .or(claims.email.as_deref())
            .unwrap_or_default()
            .to_owned(),
        name: me
            .get("name")
            .and_then(Value::as_str)
            .or(claims.name.as_deref())
            .unwrap_or_default()
            .to_owned(),
    })
}

fn verify_discovery(client: &Client) -> Result<()> {
    let document: DiscoveryDocument = checked_json(
        client.get(DISCOVERY_URL).send()?,
        "получение OIDC discovery",
    )?;
    if document.issuer != ISSUER
        || document.authorization_endpoint != AUTHORIZE_URL
        || document.token_endpoint != TOKEN_URL
        || document.jwks_uri != JWKS_URL
    {
        bail!("OIDC discovery SOFT.Connect не совпадает с доверенной конфигурацией");
    }
    Ok(())
}

fn fetch_jwks(client: &Client) -> Result<Jwks> {
    checked_json(client.get(JWKS_URL).send()?, "получение JWKS")
}

fn revoke_refresh_token(refresh_token: &str) -> Result<()> {
    let client = http_client()?;
    let form = [
        ("client_id", CLIENT_ID),
        ("token", refresh_token),
        ("token_type_hint", "refresh_token"),
    ];
    let response = client
        .post(REVOKE_URL)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&form)
        .send()?;
    if !response.status().is_success() {
        bail!("SOFT.Connect вернул HTTP {}", response.status());
    }
    Ok(())
}

fn checked_json<T: for<'de> Deserialize<'de>>(response: Response, operation: &str) -> Result<T> {
    let status = response.status();
    if !status.is_success() {
        let body = response.text().unwrap_or_default();
        let safe_error = serde_json::from_str::<Value>(&body)
            .ok()
            .and_then(|value| {
                value
                    .get("error_description")
                    .or_else(|| value.get("error"))
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
            })
            .unwrap_or_else(|| status.to_string());
        bail!("{operation}: {safe_error}");
    }
    response
        .json()
        .with_context(|| format!("{operation}: некорректный JSON"))
}

fn http_client() -> Result<Client> {
    Client::builder()
        .timeout(HTTP_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .user_agent(format!("SOFT.Connect.Desk/{}", crate::VERSION))
        .build()
        .context("не удалось создать HTTPS-клиент")
}

fn store_session(session: &VerifiedSession) -> Result<()> {
    let metadata = StoredSession {
        expires_at: session.expires_at,
        scope: session.scope.clone(),
        profile: session.profile.clone(),
    };
    let metadata = serde_json::to_string(&metadata)?;

    // The refresh token is rotated by the provider. Replacing this single native
    // credential first prevents any later code from reusing the old token.
    write_secret(REFRESH_TOKEN_ENTRY, &session.refresh_token)?;
    write_secret(ACCESS_TOKEN_ENTRY, &session.access_token)?;
    write_secret(ID_TOKEN_ENTRY, &session.id_token)?;
    write_secret(SESSION_ENTRY, &metadata)?;
    Ok(())
}

fn read_stored_session() -> Result<Option<StoredSession>> {
    let value = match read_secret_optional(SESSION_ENTRY)? {
        Some(value) => value,
        None => return Ok(None),
    };
    serde_json::from_str(&value)
        .map(Some)
        .context("повреждены метаданные защищённой OAuth-сессии")
}

fn delete_session() -> Result<()> {
    let mut errors = Vec::new();
    for entry in [
        ACCESS_TOKEN_ENTRY,
        ID_TOKEN_ENTRY,
        REFRESH_TOKEN_ENTRY,
        SESSION_ENTRY,
    ] {
        if let Err(err) = delete_secret(entry) {
            errors.push(err.to_string());
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        bail!("{}", errors.join("; "))
    }
}

fn credential_entry(name: &str) -> Result<keyring::Entry> {
    keyring::Entry::new(KEYRING_SERVICE, name)
        .map_err(|err| anyhow!("системное хранилище недоступно: {err}"))
}

fn write_secret(name: &str, value: &str) -> Result<()> {
    credential_entry(name)?
        .set_password(value)
        .map_err(|err| anyhow!("не удалось записать {name}: {err}"))
}

fn read_secret(name: &str) -> Result<String> {
    credential_entry(name)?
        .get_password()
        .map_err(|err| anyhow!("не удалось прочитать {name}: {err}"))
}

fn read_secret_optional(name: &str) -> Result<Option<String>> {
    match credential_entry(name)?.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(err) => Err(anyhow!("не удалось прочитать {name}: {err}")),
    }
}

fn delete_secret(name: &str) -> Result<()> {
    match credential_entry(name)?.delete_password() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(err) => Err(anyhow!("не удалось удалить {name}: {err}")),
    }
}

fn random_base64url_32() -> String {
    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn lock_state() -> std::sync::MutexGuard<'static, AuthState> {
    STATE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn set_error(message: String) {
    let status = if message.contains("access_denied") {
        "denied"
    } else {
        "error"
    };
    set_state(
        status,
        &message.replace("access_denied: ", ""),
        None,
        0,
        true,
    );
}

fn user_facing_error(error: &hbb_common::anyhow::Error) -> String {
    let message = format!("{error:#}");
    if message.contains("error sending request")
        || message.contains("connection")
        || message.contains("dns")
        || message.contains("timed out")
    {
        "SOFT.Connect пока недоступен. Проверьте сеть и повторите вход.".to_owned()
    } else {
        message
    }
}

fn set_state(
    status: &'static str,
    message: &str,
    profile: Option<OperatorProfile>,
    expires_at: u64,
    initialized: bool,
) {
    let snapshot = {
        let mut state = lock_state();
        state.status = status;
        state.message = message.to_owned();
        state.profile = profile;
        state.expires_at = expires_at;
        state.initialized = initialized;
        state.clone()
    };
    emit_event(json!({
        "name": "operator-auth-state",
        "state": snapshot,
    }));
}

fn emit_event(event: Value) {
    #[cfg(feature = "flutter")]
    let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, event.to_string());
    #[cfg(not(feature = "flutter"))]
    let _ = event;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oauth_random_values_have_required_length() {
        let value = random_base64url_32();
        assert_eq!(value.len(), 43);
        assert!(value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'));
    }

    #[test]
    fn audience_accepts_string_or_array() {
        assert!(audience_contains(&json!(AUDIENCE), AUDIENCE));
        assert!(audience_contains(&json!(["other", AUDIENCE]), AUDIENCE));
        assert!(!audience_contains(&json!(["other"]), AUDIENCE));
    }
}

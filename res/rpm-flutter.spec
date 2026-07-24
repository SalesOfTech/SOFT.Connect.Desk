Name:       soft-connect-desk
Version:    1.4.9
Release:    1
Summary:    SOFT.Connect.Desk remote support client
License:    AGPL-3.0-only
URL:        https://connect.salesof.tech
Vendor:     Sales Of Tech
Requires:   gtk3 libxcb libXfixes alsa-lib libva pam gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo

%description
SOFT.Connect.Desk self-hosted remote support client by Sales Of Tech.

%prep

%build

%install
mkdir -p "%{buildroot}/usr/share/soft-connect-desk"
cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* "%{buildroot}/usr/share/soft-connect-desk/"
mkdir -p "%{buildroot}/usr/bin"
ln -s /usr/share/soft-connect-desk/soft-connect-desk "%{buildroot}/usr/bin/soft-connect-desk"
install -Dm 644 $HBB/res/rustdesk.service "%{buildroot}/usr/lib/systemd/system/soft-connect-desk.service"
install -Dm 644 $HBB/res/rustdesk.desktop "%{buildroot}/usr/share/applications/soft-connect-desk.desktop"
install -Dm 644 $HBB/res/rustdesk-link.desktop "%{buildroot}/usr/share/applications/soft-connect-desk-link.desktop"
install -Dm 644 $HBB/res/icon.png "%{buildroot}/usr/share/icons/hicolor/1024x1024/apps/soft-connect-desk.png"

%files
/usr/share/soft-connect-desk/*
/usr/bin/soft-connect-desk
/usr/lib/systemd/system/soft-connect-desk.service
/usr/share/applications/soft-connect-desk.desktop
/usr/share/applications/soft-connect-desk-link.desktop
/usr/share/icons/hicolor/1024x1024/apps/soft-connect-desk.png

%post
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable soft-connect-desk.service >/dev/null 2>&1 || true
update-desktop-database >/dev/null 2>&1 || true

%preun
if [ "$1" -eq 0 ]; then
  systemctl stop soft-connect-desk.service >/dev/null 2>&1 || true
  systemctl disable soft-connect-desk.service >/dev/null 2>&1 || true
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || true
update-desktop-database >/dev/null 2>&1 || true

%changelog
* Fri Jul 24 2026 Sales Of Tech <support@salesof.tech> - 1.4.9-1
- Branded SOFT.Connect.Desk package

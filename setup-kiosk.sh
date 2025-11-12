sudo bash -c '
echo "Setting up kiosk permissions and files..."

# === 1. Create required directories ===
mkdir -p /var/www/html/bg
chown www-data:www-data /var/www/html /var/www/html/bg
chmod 755 /var/www/html
chmod 775 /var/www/html/bg

# === 2. Create default files if missing ===
[ ! -f /var/www/html/specials.txt ] && echo -e "Today'\''s Specials:\n- Burger \$12\n- Salad \$9" > /var/www/html/specials.txt
[ ! -f /var/www/html/config.json ] && cat > /var/www/html/config.json << EOF
{
  "bg": "bg1.jpg",
  "font": "'Comic Sans MS', cursive"
}
EOF

# === 3. Set ownership & permissions for all files ===
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 775 /var/www/html/bg
chmod 664 /var/www/html/specials.txt
chmod 664 /var/www/html/config.json

# === 4. Ensure PHP scripts exist and are correct ===
cat > /var/www/html/upload-bg.php << '\''EOF'\''
<?php
header(''Content-Type: application/json'');
if ($_SERVER[''REQUEST_METHOD''] !== ''POST'') { http_response_code(405); echo json_encode([''error''=>''Method not allowed'']); exit; }
if (!isset($_FILES[''image'']) || $_FILES[''image''][''error''] !== UPLOAD_ERR_OK) { http_response_code(400); echo json_encode([''error''=>''No image'']); exit; }
$file = $_FILES[''image''];
$ext = strtolower(pathinfo($file[''name''], PATHINFO_EXTENSION));
$allowed = [''jpg'',''jpeg'',''png'',''gif'',''webp''];
if (!in_array($ext, $allowed)) { http_response_code(400); echo json_encode([''error''=>''Invalid type'']); exit; }
$filename = ''uploaded_'' . time() . ''_'' . bin2hex(random_bytes(4)) . ''.'' . $ext;
$path = __DIR__ . ''/bg/'' . $filename;
if (!move_uploaded_file($file[''tmp_name''], $path)) { http_response_code(500); echo json_encode([''error''=>''Save failed'']); exit; }
echo json_encode([''filename'' => $filename]);
?>
EOF

cat > /var/www/html/bg/index.php << '\''EOF'\''
<?php
header(''Content-Type: application/json'');
$files = array_diff(scandir(''.''), [''.'', ''..'', ''index.php'']);
$images = array_filter($files, function($f) { return preg_match(''/\\.(jpe?g|png|gif|webp)$/i'', $f); });
echo json_encode(array_values($images));
?>
EOF

chown www-data:www-data /var/www/html/upload-bg.php /var/www/html/bg/index.php
chmod 644 /var/www/html/upload-bg.php /var/www/html/bg/index.php

# === 5. Configure lighttpd: WebDAV + ETag ===
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"
WEBDAV_CONF="/etc/lighttpd/conf-enabled/10-webdav.conf"

# Enable ETag
if ! grep -q "server.etag" "$LIGHTTPD_CONF"; then
  echo "server.etag = \"enable\"" >> "$LIGHTTPD_CONF"
fi

# WebDAV: only allow specific files
cat > "$WEBDAV_CONF" << '\''EOF'\''
server.modules += ( "mod_webdav" )

$HTTP["url"] =~ "^/(index\\.html|config\\.json|specials\\.txt)$" {
    webdav.activate = "enable"
    webdav.is-readonly = "disable"
}
EOF

# === 6. Restart lighttpd ===
systemctl restart lighttpd

# === 7. Add sample background (if none exist) ===
if [ -z "$(ls -A /var/www/html/bg/*.jpg 2>/dev/null)" ]; then
  echo "Adding sample background..."
  wget -q -O /var/www/html/bg/bg1.jpg https://images.unsplash.com/photo-1504674900247-0877df9cc836
  chown www-data:www-data /var/www/html/bg/bg1.jpg
  chmod 644 /var/www/html/bg/bg1.jpg
fi

echo "All permissions and files are now correctly set!"
echo "Open: http://raspberrypi.local/index.html"
'

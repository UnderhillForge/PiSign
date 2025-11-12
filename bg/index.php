<?php
header('Content-Type: application/json');
$files = scandir('.');
$images = array_filter($files, function($f) {
    return preg_match('/\.(jpe?g|png|gif|webp)$/i', $f) && !is_dir($f);
});
echo json_encode(array_values($images));
?>
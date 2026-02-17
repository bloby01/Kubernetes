<?php
$server_ip = $_SERVER['SERVER_ADDR'] ?? gethostbyname(gethostname());
?>
<!DOCTYPE html>
<html>
<head>
    <title>Test App</title>
</head>
<body>
    <h1>Coucou</h1>
    <p>Adresse IP du serveur : <strong><?php echo htmlspecialchars($server_ip); ?></strong></p>
</body>
</html>

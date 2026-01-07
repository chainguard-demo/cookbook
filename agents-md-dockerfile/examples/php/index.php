<?php

$host = getenv('HOST') ?: '0.0.0.0';
$port = getenv('PORT') ?: 8080;

echo "Server running at http://{$host}:{$port}/\n";

// Simple HTTP server handler
$handler = function () {
    echo "Hello from Chainguard PHP image!\n";
    echo "PHP Version: " . phpversion() . "\n";
};

// Start the built-in PHP web server
if (php_sapi_name() === 'cli-server') {
    $handler();
} else {
    // For CLI, start the server
    $command = sprintf(
        'php -S %s:%d %s',
        $host,
        $port,
        __FILE__
    );
    passthru($command);
}

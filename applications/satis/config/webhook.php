<?php

$secret = getenv('WEBHOOK_SECRET');
$payload = file_get_contents('php://input');
$signature = $_SERVER['HTTP_X_HUB_SIGNATURE_256'] ?? '';

// Valida assinatura do GitHub
$expected = 'sha256=' . hash_hmac('sha256', $payload, $secret);
if (!hash_equals($expected, $signature)) {
    http_response_code(401);
    echo json_encode(['error' => 'Assinatura inválida']);
    exit;
}

$data = json_decode($payload, true);

// Aceita push em main/master ou tags (refs/tags/*)
$ref = $data['ref'] ?? '';
$isBranch = in_array($ref, ['refs/heads/main', 'refs/heads/master']);
$isTag = str_starts_with($ref, 'refs/tags/');

if (!$isBranch && !$isTag) {
    echo json_encode(['status' => 'ignorado', 'ref' => $ref]);
    exit;
}

$triggerType = $isTag ? 'tag push' : 'branch push';
$repo = $data['repository']['full_name'] ?? 'desconhecido';
error_log("[satis-webhook] Rebuild disparado por {$triggerType}: {$ref} ({$repo})");

// Dispara rebuild em background
exec('nohup /usr/local/bin/satis-build >> /var/log/satis-build.log 2>&1 &');

http_response_code(200);
echo json_encode([
    'status'     => 'rebuild iniciado',
    'trigger'    => $triggerType,
    'repository' => $repo,
    'ref'        => $ref,
]);

<?php
// Stale-state probe. Without ?start=1 it does NOT call session_start(), so it
// reports exactly what request startup left behind in the worker. With
// ?start=1 it behaves like the next request of any *other* client: no cookie
// sent, so a session id can only come from the worker's stale state.
header('Content-Type: application/json');
header('Cache-Control: no-store');

$started = isset($_GET['start']) && $_GET['start'] === '1';
$pre = [
    'pid' => getmypid(),
    'session_status_before' => session_status(),
    'session_id_before' => session_id(),
    'globals_before' => array_key_exists('_SESSION', $GLOBALS),
];
if ($started) {
    $ok = @session_start();
    $pre['session_start_result'] = $ok;
    $pre['session_start_warning'] = error_get_last()['message'] ?? null;
}

echo json_encode($pre + [
    'session_status' => session_status(),
    'session_id' => session_id(),
    'globals_SESSION' => array_key_exists('_SESSION', $GLOBALS),
    'SESSION' => array_key_exists('_SESSION', $GLOBALS) ? $_SESSION : null,
    'POST' => $_POST,
    'FILES' => $_FILES,
    'ob_level' => ob_get_level(),
    'headers_already_sent' => headers_sent(),
], JSON_PARTIAL_OUTPUT_ON_ERROR);

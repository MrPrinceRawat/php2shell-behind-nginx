<?php
// FPM identity probe: pid, pool worker, and whether the parse-time session
// state was inherited.
header('Content-Type: application/json');
header('Cache-Control: no-store');
echo json_encode([
    'sapi' => PHP_SAPI,
    'pid' => getmypid(),
    'status_before' => session_status(),
    'id_before' => session_id(),
    'globals_before' => array_key_exists('_SESSION', $GLOBALS),
    'SESSION' => array_key_exists('_SESSION', $GLOBALS) ? $_SESSION : null,
], JSON_PARTIAL_OUTPUT_ON_ERROR);

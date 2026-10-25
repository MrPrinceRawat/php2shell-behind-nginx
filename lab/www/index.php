<?php
// A boring, realistic page: the only thing it does is touch the session.
// Exploitation must not depend on any app logic, because the corruption
// happens in request startup, before this file is even compiled.
session_start();
$_SESSION['hits'] = ($_SESSION['hits'] ?? 0) + 1;
echo "index ok, hits=", $_SESSION['hits'], ", sid=", session_id(), "\n";

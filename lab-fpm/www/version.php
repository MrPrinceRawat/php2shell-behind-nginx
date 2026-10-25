<?php
// Identifies the target build, so every capture proves which version was hit.
header('Content-Type: text/plain');
printf("php=%s\n", PHP_VERSION);
printf("sapi=%s\n", PHP_SAPI);
printf("zts=%d\n", PHP_ZTS);
printf("memory_limit=%s post_max_size=%s upload_max_filesize=%s\n",
    ini_get('memory_limit'), ini_get('post_max_size'), ini_get('upload_max_filesize'));
printf("session.upload_progress.enabled=%s cleanup=%s\n",
    ini_get('session.upload_progress.enabled'), ini_get('session.upload_progress.cleanup'));
printf("display_errors=%s\n", ini_get('display_errors'));

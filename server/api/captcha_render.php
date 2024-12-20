<?php

$disable_database = true;
require_once('_captcha.php');

if (empty($_REQUEST['page']) || empty($_REQUEST['captchaid'])) {
    die_error('Missing parameters', 400);
}

$captcha = DSOCaptcha::fromSession($_REQUEST['page'], $_REQUEST['captchaid']);
$captcha->render();

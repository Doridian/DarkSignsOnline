<?php

require_once('_captcha.php');

$captcha = new DSOCaptcha($_REQUEST['page'], $_REQUEST['captchaid']);
$captcha->render();

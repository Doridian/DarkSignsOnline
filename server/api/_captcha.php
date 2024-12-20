<?php

require_once('function_base.php');
session_start();

define('CAPTCHA_EXPIRY_SECONDS', 300);
define('CAPTCHA_WIDTH', 200);
define('CAPTCHA_HEIGHT', 50);
define('CAPTCHA_LENGTH', 6);
define('CAPTCHA_FONT_SIZE', 24);

class DSOCaptcha {
    private $code;
    private $hmac;
    private $timestamp;
    private $page;

    public function __construct($page, $id = null) {
        if (empty($id)) {
            $this->code = make_keycode(CAPTCHA_LENGTH, '23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
            $this->timestamp = time();
            $this->page = $page;
            $this->hmac = $this->hash($this->code);
            $_SESSION[$this->sessionKey()] = $this->sessionValue();
        } else {
            list($this->hmac, $this->page, $timestamp_str) = explode(';', $id, 3);
            $this->timestamp = intval($timestamp_str);
            $this->code = @$_SESSION[$this->sessionKey()];
        }
    }

    private function sessionKey() {
        return 'captcha_' . $this->page;
    }

    private function sessionValue() {
        return $this->code;
    }

    private function hash($code) {
        global $CAPTCHA_SECRET_KEY;
        return hash_hmac('sha256', $code . ';' . $this->page . ';' . strval($this->timestamp), $CAPTCHA_SECRET_KEY);
    }

    public function check($code) {
        if (time() - $this->timestamp > CAPTCHA_EXPIRY_SECONDS) {
            return false;
        }

        $code = trim(strtoupper($code));

        if (!hash_equals($this->hmac, $this->hash($code))) {
            return false;
        }
        if (@$_SESSION[$this->sessionKey()] !== $this->sessionValue()) {
            return false;
        }
        unset($_SESSION[$this->sessionKey()]);
        return true;
    }

    public function getID() {
        return $this->hmac . ';' . $this->page . ';' . strval($this->timestamp);
    }

    public function render() {
        global $CAPTCHA_FONT;
        if (empty($this->code)) {
            throw new Exception('No image code set');
        }

        $img = imagecreatetruecolor(CAPTCHA_WIDTH, CAPTCHA_HEIGHT);
        $bg = imagecolorallocate($img, 0, 0, 0);
        $textcolor = imagecolorallocate($img, 255, 255, 255);
        imagefilledrectangle($img, 0, 0, CAPTCHA_WIDTH, CAPTCHA_HEIGHT, $bg);

        $per_char_width = CAPTCHA_WIDTH / CAPTCHA_LENGTH;
        for ($i = 0; $i < CAPTCHA_LENGTH; $i++) {
            imagettftext($img, CAPTCHA_FONT_SIZE, rand(-15, 15), ($per_char_width * $i) + rand(0, 10), rand(CAPTCHA_HEIGHT - CAPTCHA_FONT_SIZE, CAPTCHA_HEIGHT), $textcolor, $CAPTCHA_FONT, $this->code[$i]);
        }

        header('Content-Type: image/png');
        imagepng($img);
        imagedestroy($img);
    }
}

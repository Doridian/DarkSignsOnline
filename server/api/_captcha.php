<?php

require_once('function_base.php');
session_start();

define('CAPTCHA_EXPIRY_SECONDS', 300);
define('CAPTCHA_WIDTH', 200);
define('CAPTCHA_HEIGHT', 50);
define('CAPTCHA_LENGTH', 6);
define('CAPTCHA_FONT_SIZE', 24);

class DSOCaptcha {
    private $id;
    private $page;
    private $expiry;
    private $code;

    private function __construct($page, $id, $expiry, $code) {
        $this->page = $page;
        $this->id = $id;
        $this->expiry = $expiry;
        $this->code = $code;
    }

    public static function createNew($page) {
        $id = make_keycode(64);
        $expiry = time() + CAPTCHA_EXPIRY_SECONDS;
        $code = make_keycode(CAPTCHA_LENGTH, '23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
        $obj = new DSOCaptcha($page, $id, $expiry, $code);
        $_SESSION[$obj->sessionKey()] = strval($obj->expiry) . '|' . $obj->code;
        return $obj;
    }

    public static function loadFromSession($page, $id) {
        $obj = new DSOCaptcha($page, $id, 0, '');
        $data = @$_SESSION[$obj->sessionKey()];
        if (!empty($data)) {
            list($expiry_str, $obj->code) = explode('|', $data);
            $obj->expiry = intval($expiry_str);
        }
        return $obj;
    }

    private function sessionKey() {
        return 'captcha_' . $this->page . '_' . $this->id;
    }

    private function unsetSessionKey() {
        unset($_SESSION[$this->sessionKey()]);
    }

    public function check($code) {
        if (time() > $this->expiry) {
            $this->unsetSessionKey();
            return false;
        }

        $this->unsetSessionKey();
        return strcmp($this->code, $code) === 0;
    }

    public function getID() {
        return $this->id;
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

        $e = new \Random\Engine\Mt19937($this->expiry);
        $r = new \Random\Randomizer($e);
        $per_char_width = CAPTCHA_WIDTH / CAPTCHA_LENGTH;
        for ($i = 0; $i < CAPTCHA_LENGTH; $i++) {
            imagettftext($img, CAPTCHA_FONT_SIZE + $r->getInt(-2, 2), $r->getFloat(-15, 15), ($per_char_width * $i) + $r->getFloat(0, 10), $r->getFloat(CAPTCHA_HEIGHT - CAPTCHA_FONT_SIZE, CAPTCHA_HEIGHT), $textcolor, $CAPTCHA_FONT, $this->code[$i]);
        }

        header('Content-Type: image/png');
        imagepng($img);
        imagedestroy($img);
    }
}

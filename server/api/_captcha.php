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

    public function regenerate() {
        return DSOCaptcha::createNew($this->page);
    }

    public static function fromPOSTData($page) {
        $id = @$_POST['captchaid'];
        if (empty($id)) {
            $id = '';
        }
        return DSOCaptcha::fromID($page, $id);
    }

    public static function fromID($page, $id) {
        $obj = new DSOCaptcha($page, $id, 0, '');
        if (empty($id)) {
            // Return always-invalid expiry 0 CAPTCHA
            return $obj;
        }

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

    public function checkPOSTData() {
        $code = @$_POST['captchacode'];
        if (empty($code)) {
            return false;
        }
        return $this->check($code);
    }

    public function check($code) {
        $code = strtoupper(trim($code));

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

    public function imageURL() {
        return 'api/captcha_render.php?page=' . urlencode($this->page) .
                '&captchaid=' . urlencode($this->id);
    }

    public function image() {
        return '<img src="' . htmlspecialchars($this->imageURL()) . '" />';
    }

    public function idField() {
        return '<input type="hidden" name="captchaid" value="' . htmlspecialchars($this->id) . '" />';
    }

    public function formField() {
        return '<input name="captchacode" id="captchacode" type="text" required="required" />';
    }

    public function render() {
        global $CAPTCHA_FONT;
        if (empty($this->code)) {
            throw new Exception('No image code set');
        }

        $img = imagecreatetruecolor(CAPTCHA_WIDTH, CAPTCHA_HEIGHT);
        $bg = imagecolorallocate($img, 0, 0, 0);
        $textcolors = [
            imagecolorallocate($img, 242, 201, 6),
            imagecolorallocate($img, 255, 255, 255),
        ];
        $textcolor_max = count($textcolors) - 1;
        imagefilledrectangle($img, 0, 0, CAPTCHA_WIDTH, CAPTCHA_HEIGHT, $bg);

        $e = new \Random\Engine\Mt19937($this->expiry);
        $r = new \Random\Randomizer($e);
        $per_char_width = CAPTCHA_WIDTH / CAPTCHA_LENGTH;
        for ($i = 0; $i < CAPTCHA_LENGTH; $i++) {
            imagettftext(
                $img,
                CAPTCHA_FONT_SIZE + $r->getInt(-2, 2),
                $r->getFloat(-15, 15),
                ($per_char_width * $i) + $r->getFloat(0, 10),
                $r->getFloat(CAPTCHA_HEIGHT - CAPTCHA_FONT_SIZE, CAPTCHA_HEIGHT),
                $textcolors[$r->getInt(0, $textcolor_max)],
                $CAPTCHA_FONT,
                $this->code[$i]
            );
        }

        header('Content-Type: image/png');
        imagepng($img);
        imagedestroy($img);
    }
}

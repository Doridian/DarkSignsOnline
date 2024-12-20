<?php

require_once('function_base.php');
session_start();

define('CAPTCHA_EXPIRY_SECONDS', 300);

class DSOCaptcha {
    private $code;
    private $hmac;
    private $timestamp;
    private $page;

    public function __construct($page, $id = null) {
        if (empty($id)) {
            $this->code = make_keycode(8, '23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
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
        if (empty($this->code)) {
            throw new Exception('No image code set');
        }
        echo 'TODO: CAPTCHA';
    }
}

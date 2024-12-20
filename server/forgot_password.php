<?php

$htmltitle = 'Forgot password';
require_once('api/function_base.php');
require_once('api/_captcha.php');
require('_top.php');

if (!empty($_POST['email']) && !empty($_POST['username'])) {
    $captcha = new DSOCaptcha('forgot_password', $_POST['captchaid']);
    if (!$captcha->check($_POST['captchacode'])) {
        die_frontend_msg('The CAPTCHA code you entered was incorrect.');
    }

    $username = strtolower(trim($_POST['username']));
    $email = trim($_POST['email']);

    $stmt = $db->prepare('SELECT id, username FROM users WHERE email=? AND username=?');
    $stmt->bind_param('ss', $email, $username);
    $stmt->execute();
    $res = $stmt->get_result();
    $user = $res->fetch_assoc();

    if (!$user) {
        die_frontend_msg('Error, no user with this E-Mail and username not found.');
    }

    $username = $user['username']; // Re-grab from DB

    $vercode = make_keycode();
    $expiry = time() + 3600;
    $stmt = $db->prepare('INSERT INTO email_codes (user, code, expiry, action) VALUES (?, ?, ?, "forgot_password")');
    $stmt->bind_param('isi', $user['id'], $vercode, $expiry);
    $stmt->execute();

    $headers = "From: Dark Signs Online <noreply@darksignsonline.com>\r\n";
    mail($email, "Dark Signs Online - Password reset for $username", "Hi $username,\n\nYou (or someone who knows your E-Mail) has reuqested a password reset for your account, $username\n\nClick the link below to change your password, or ignore this E-Mail if you didn't initiate this change.\n\nhttps://darksignsonline.com/forgot_password2.php?code=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/", $headers);

    die_frontend_msg('E-Mail has been sent!', 'Check your E-Mail for the password reset link.');
}

$captcha = new DSOCaptcha('forgot_password');
?>

<font face="Georgia, Times New Roman, Times, serif" size="+3">Forgot password</font><br />
<br />


<form action="forgot_password.php" method="post">
    <table width="546" border="0" cellpadding="10" cellspacing="0" bgcolor="#003366">
        <tr>
            <td>
                <div align="left">
                    <label for="username">
                        <font face='verdana'><strong>Username</strong></font>
                    </label>
                </div>
            </td>
            <td>
                <div align="left"><input name="username" id="username" type="text" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td bgcolor="#004488">
                <div align="left">
                    <label for="email">
                        <font face='verdana'><strong>E-Mail Address</strong></font>
                    </label>
                </div>
            </td>
            <td bgcolor="#004488">
                <div align="left"><input name="email" id="email" type="email" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td>
                <div align="left">
                    <label for="captchacode">
                        <font face='verdana'><strong>CAPTCHA</strong></font>
                        <img src="api/captcha_render.php?page=forgot_password&id=<?php echo htmlspecialchars($captcha->getID()); ?>" />
                    </label>
                </div>
            </td>
            <td>
                <div align="left"><input name="captchacode" id="captchacode" type="text" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td bgcolor="#004488">
                <div align="left">
                    <font face='verdana'></font>
                </div>
            </td>
            <td bgcolor="#004488">
                <div align="left">
                    <input type="hidden" name="captchaid" value="<?php echo htmlspecialchars($captcha->getID()); ?>" />
                    <input type="submit" value="Send E-Mail" />
                </div>
            </td>
        </tr>

    </table>
</form>
<br />
<br />
<?php require("_bottom.php");

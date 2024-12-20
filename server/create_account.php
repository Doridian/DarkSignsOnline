<?php

$htmltitle = 'Create a new account';
require_once('api/function_base.php');
require_once('api/_captcha.php');
require('_top.php');

if (!empty($_POST['username']) && !empty($_POST['captchaid'])) {
    $captcha = DSOCaptcha::fromSession('create_account', $_POST['captchaid']);
    if (!$captcha->check($_POST['captchacode'])) {
        die_frontend_msg('The CAPTCHA code you entered was incorrect.');
    }

    if ($_POST['agreetos'] !== 'yes' || $_POST['agecheck'] !== 'yes') {
        die_frontend_msg('You must agree to the terms of use and confirm you are at least 13 years old.');
    }

    $username = strtolower(trim($_POST['username']));
    $password = $_POST['password'];
    $email = trim($_POST['email']);

    $username = str_replace(' ', '-', $username);

    if (strlen($username) < 3) {
        die_frontend_msg("Your username must be at least 3 characters long.");
    }
    if (strlen($username) > 20) {
        die_frontend_msg("Your username must be at most 20 characters long.");
    }
    if (strlen($password) < 6) {
        die_frontend_msg("Your password must be at least 6 characters long.");
    }

    if (!preg_match('/^[A-Za-z0-9-]+$/', $username)) die_frontend_msg("Error, please don't use invalid characters in your username.");

    $pwhash = password_hash($password, PASSWORD_DEFAULT);

    $db->begin_transaction();
    //check if email already exists
    $stmt = $db->prepare("SELECT id from users where email=?");
    $stmt->bind_param('s', $email);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $db->rollback();
        $email = htmlentities($email);
        die_frontend_msg("The email address <b>$email</b> already exists in the database. Please try again.");
    }
    //check if username already exists
    $stmt = $db->prepare("SELECT id from users where username=?");
    $stmt->bind_param('s', $username);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $db->rollback();
        $username = htmlentities($username);
        die_frontend_msg("The username <b>$username</b> already exists in the database. Please try again.");
    }
    //insert the data

    $aip = $_SERVER['REMOTE_ADDR'];
    $vercode = make_keycode();
    $timestamp = time();

    $stmt = $db->prepare('INSERT INTO users (username, password, email, createtime, ip, lastseen, emailverifycode, active, cash) VALUES (?,?,?,?,?,?,?,0,200)');
    if (!$stmt) {
        $db->rollback();
        die_frontend_msg('Database error, please try again');
    }
    $stmt->bind_param('sssisis', $username, $pwhash, $email, $timestamp, $aip, $timestamp, $vercode);
    $stmt->execute();
    $res = $stmt->get_result();
    $userid = $db->insert_id;

    make_new_domain('DOMAIN', '', $userid, $username . '.usr');

    $db->commit();

    $headers = "From: Dark Signs Online <noreply@darksignsonline.com>\r\n";
    mail($email, "$username, verify your Dark Signs Online Account", "Hi $username,\n\nThank you for creating an account on Dark Signs Online!\n\nClick the link below to activate your account.\n\nhttps://darksignsonline.com/verify.php?code=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/", $headers);

    die_frontend_msg('Your account has been created!', 'Check your E-Mail for more information.');
}

$captcha = DSOCaptcha::createNew('create_account');
?>

<font face="Georgia, Times New Roman, Times, serif" size="+3">Create a new account</font><br />
<br />


<form action="create_account.php" method="post">
    <table width="546" border="0" cellpadding="10" cellspacing="0" bgcolor="#003366">
        <tr>
            <td width="281">
                <div align="left">
                    <label for="username">
                        <font face='verdana'><strong>Username</strong><br />
                            <font size="2">Try to be unique.<br />
                                Do not use spaces, underscores, or other strange characters. You may use dashes.</font>
                        </font><br />
                    </label>
                </div>
            </td>
            <td width="245">
                <div align="left"><input type="text" id="username" name="username" required="required" /></div>
            </td>
        </tr>
        <tr>
            <td bgcolor="#004488">
                <div align="left">
                    <label for="password">
                        <font face='verdana'><strong>Password</strong></font>
                    </label>
                </div>
            </td>
            <td bgcolor="#004488">
                <div align="left"><input type="password" id="password" name="password" required="required" /></div>
            </td>
        </tr>
        <tr>
            <td>
                <div align="left">
                    <label for="email">
                        <font face='verdana'><strong>E-Mail Address</strong>
                            <font size="2"><br />
                                This must be a valid e-mail address, or you will not be able to log in. </font>
                        </font>
                    </label>
                </div>
            </td>
            <td>
                <div align="left"><input name="email" id="email" type="email" required="required" /></div>
            </td>
        </tr>
        <tr>
            <td bgcolor="#004488">
                <div align="left">
                    <label for="agreetos">
                        <font face="Verdana" size="2"><strong>I have read and agree to the <a
                                    href="termsofuse.php" target="_blank" style="color:#DDE8F9">Dark Signs Online Terms of Use</a></strong></font>
                    </label>
                </div>
            </td>
            <td bgcolor="#004488">
                <div align="left">
                    <input type="checkbox" id="agreetos" name="agreetos" value="yes" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td>
                <div align="left">
                    <label for="agecheck">
                        <font face="Verdana" size="2"><strong>I am at least 13 years old</strong></font>
                    </label>
                </div>
            </td>
            <td>
                <div align="left">
                    <input type="checkbox" id="agecheck" name="agecheck" value="yes" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td bgcolor="#004488">
                <div align="left">
                    <label for="captchacode">
                        <font face='verdana'><strong>CAPTCHA</strong></font>
                        <img src="api/captcha_render.php?page=create_account&captchaid=<?php echo htmlspecialchars($captcha->getID()); ?>" />
                    </label>
                </div>
            </td>
            <td bgcolor="#004488">
                <div align="left"><input name="captchacode" id="captchacode" type="text" required="required" />
                </div>
            </td>
        </tr>
        <tr>
            <td>
                <div align="left">
                    <font face='verdana'></font>
                </div>
            </td>
            <td>
                <div align="left">
                    <input type="hidden" name="captchaid" value="<?php echo htmlspecialchars($captcha->getID()); ?>" />
                    <input type="submit" value="Create the account..." />
                </div>
            </td>
        </tr>
    </table>
</form>
<br />
<br />
<?php require("_bottom.php");

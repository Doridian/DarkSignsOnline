<?php

$htmltitle = 'Forgot password';
require('_top.php');
require_once('api/function_base.php');

if (isset($_POST['email'])) {
    $email = strtolower(trim($_POST['email']));

    $stmt = $db->prepare('SELECT id FROM users WHERE email=?');
    $stmt->bind_param('s', $email);
    $stmt->execute();
    $res = $stmt->get_result();
    $user = $res->fetch_assoc();

    if (!$user) {
        echo "<center><br><br><font size='4' color='orange' face='arial'><b>Error, no user with this E-Mail not found.</b></font></center>";
        require('_bottom.php');
        exit;
    }

    $vercode = make_keycode();
    $expiry = time() + 3600;
    $stmt = $db->prepare('INSERT INTO email_codes (user, code, expiry, action) VALUES (?, ?, ?, "forgot_password")');
    $stmt->bind_param('isi', $user['id'], $vercode, $expiry);
    $stmt->execute();

	$headers = "From: Dark Signs Online <noreply@darksignsonline.com>\r\n";
	mail($email, "Dark Signs Online - Password reset for $username", "Hi $username,\n\nYou (or someone who knows your E-Mail) has reuqested a password reset for your account, $username\n\nClick the link below to change your password, or ignore this E-Mail if you didn't initiate this change.\n\nhttps://darksignsonline.com/forgot_password2.php?code=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/", $headers);

	echo "<center><br><br><font size='4' color='orange' face='arial'><b>E-Mail has been sent!</b><br>Check your email for the password reset link.</font></center>";
	require('_bottom.php');
	exit;
}

?>

<font face="Georgia, Times New Roman, Times, serif" size="+3">Forgot password</font><br />
<br />


<form action="forgot_password.php" method="post">
	<table width="546" border="0" cellpadding="10" cellspacing="0" bgcolor="#003366">
		<tr>
			<td>
				<div align="left">
					<font face='verdana'><strong>Email Address</strong></font>
				</div>
			</td>
			<td>
				<div align="left"><input name="email" type="text" size="35" />
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
					<font face="Verdana" size="1"><strong>By creating an account, you agree to the <a
								href="termsofuse.php" target="_blank" style="color:#DDE8F9">Dark Signs Online TERMS OF
								USE</a>.</strong></font><br />
					<br />
					<input type="submit" value="Create the account..." />
				</div>
			</td>
		</tr>

	</table>
</form>
<br />
<br />
<?php require("_bottom.php");

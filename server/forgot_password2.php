<?php

$htmltitle = 'Forgot password';
require('_top.php');
require_once('api/function_base.php');

if (empty($_REQUEST['code'])) {
	die('Error, no code provided.');
}

$time = time();
$stmt = $db->prepare('SELECT user FROM email_codes WHERE code = ? AND expiry >= ? AND action="forgot_password"');
$stmt->bind_param('si', $_REQUEST['code'], $time);
$stmt->execute();

$res = $stmt->get_result();
$row = $res->fetch_assoc();
if (!$row) {
	die('Error, invalid code.');
}

$stmt = $db->prepare('SELECT username, email FROM users WHERE id = ?');
$stmt->bind_param('i', $row['user']);
$stmt->execute();
$res = $stmt->get_result();
$user = $res->fetch_assoc();
if (!$user) {
	die('Error, invalid user.');
}

if (!empty($_POST['password'])) {
	$password = $_POST['password'];
	if (strlen($password) < 6) {
		die("Your password must be at least 6 characters long.");
	}

	$stmt = $db->prepare('DELETE FROM email_codes WHERE code=?');
	$stmt->bind_param('s', $_REQUEST['code']);
	$stmt->execute();

	$pwhash = password_hash($password, PASSWORD_DEFAULT);

	$stmt = $db->prepare('UPDATE users SET password=? WHERE id=?');
	$stmt->bind_param('si', $pwhash, $row['user']);
	$stmt->execute();

	echo "<center><br><br><font size='4' color='orange' face='arial'><b>Password has been changed!</b></font></center>";
	require('_bottom.php');
	exit;
}

?>

<font face="Georgia, Times New Roman, Times, serif" size="+3">Forgot password</font><br />
<br />


<form action="forgot_password2.php" method="post">
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
				<div align="left"><input name="username" id="username" type="text" disabled="disabled" value="<?php echo htmlspecialchars($user['username']); ?>" />
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
				<div align="left"><input name="email" id="email" type="email" disabled="disabled" value="<?php echo htmlspecialchars($user['email']); ?>" />
				</div>
			</td>
		</tr>
		<tr>
			<td>
				<div align="left">
					<label for="password">
						<font face='verdana'><strong>Password</strong></font>
					</label>
				</div>
			</td>
			<td>
				<div align="left"><input type="password" id="password" name="password" required="required" /></div>
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
					<input type="hidden" name="code" value="<?php echo htmlspecialchars($_REQUEST['code']); ?>" />
					<input type="submit" value="Change password" />
				</div>
			</td>
		</tr>

	</table>
</form>
<br />
<br />
<?php require("_bottom.php");

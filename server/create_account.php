<?php

$rewrite_done = true;

$htmltitle = 'Create a new account';
require('_top.php');
require_once('api/function_base.php');

if (isset($_POST['username'])) {
	$username = strtolower(trim($_POST['username']));
	$password = trim($_POST['password']);
	$email = trim($_POST['email']);
	$dobday = trim($_POST['dobday']);
	$dobmonth = trim($_POST['dobmonth']);
	$dobyear = trim($_POST['dobyear']);

	$username = str_replace(" ", "-", trim($username));

	if (strstr($username, "_")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ">")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "~")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "!")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "`")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "@")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "#")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "$")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "%")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "^")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "&")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "*")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "<")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "/")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "\\")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "(")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ")")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "_")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "+")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "=")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "[")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "{")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "]")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "}")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "|")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ":")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ";")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "\"")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "'")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, "?")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ",")) {
		die("Error, please don't use invalid characters in your username.");
	}
	if (strstr($username, ".")) {
		die("Error, please don't use invalid characters in your username.");
	}

	//check password length
	if (strlen($password) < 6) {
		die("Your password should be at least 6 characters long.");
	}

	$password = password_hash($password, PASSWORD_DEFAULT);

	$db->begin_transaction();
	//check if email already exists
	$stmt = $db->prepare("SELECT id from users where email=?");
	$stmt->bind_param('s', $email);
	$stmt->execute();
	if ($stmt->get_result()->num_rows > 0) {
		$db->rollback();
		$email = htmlentities($email);
		die("The email address <b>$email</b> already exists in the database. Please try again.");
	}
	//check if username already exists
	$stmt = $db->prepare("SELECT id from users where username=?");
	$stmt->bind_param('s', $username);
	$stmt->execute();
	if ($stmt->get_result()->num_rows > 0) {
		$db->rollback();
		$username = htmlentities($username);
		die("The username <b>$username</b> already exists in the database. Please try again.");
	}

	//insert the data

	$aip = $_SERVER['REMOTE_ADDR'];
	$vercode = make_keycode();
	$timestamp = time();

	$stmt = $db->prepare('INSERT INTO users (username, password, email, createtime, ip, lastseen, dobday, dobmonth, dobyear, emailverifycode, active, cash) VALUES (?,?,?,?,?,?,?,?,?,?,0,200)');
	if (!$stmt) {
		$db->rollback();
		die("Error: " . $db->error);
	}
	$stmt->bind_param('sssisiiiis', $username, $password, $email, $timestamp, $aip, $timestamp, $dobday, $dobmonth, $dobyear, $vercode);
	$stmt->execute();
	$res = $stmt->get_result();
	$userid = $db->insert_id;

	$id = makeNewIP('DOMAIN', '', $userid);
	$stmt = $db->prepare("INSERT INTO domain (id, name, ext) VALUES (?, ?, 'usr')");
	$stmt->bind_param('is', $id, $username);
	$stmt->execute();

	$db->commit();

	$headers = "From: Dark Signs Online <noreply@darksignsonline.com>\r\n";
	mail($email, "$username, verify your Dark Signs Account", "Hi $username,\n\nThank you for creating an account on Dark Signs Online!\n\nClick the link below to activate your account.\n\nhttps://darksignsonline.com/verify.php?code=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/", $headers);

	echo "<center><br><br><font size='4' color='orange' face='arial'><b>Your account has been created!</b><br>Check your email address for more information.</font></center>";
	require('_bottom.php');
	exit;
}

?>

<font face="Georgia, Times New Roman, Times, serif" size="+3">Create a new account</font><br />
<br />


<form action="create_account.php" method="post">
	<table width="546" border="0" cellpadding="10" cellspacing="0" bgcolor="#003366">
		<tr>
			<td width="281">
				<div align="left">
					<font face='verdana'><strong>Username</strong><br />
						<font size="2">Try to be unique.<br />
							Do not use spaces, underscores, or other strange characters. You may use dashes. </font>
					</font><br />

				</div>
			</td>
			<td width="245">
				<div align="left"><input type="text" name="username" /></div>
			</td>
		</tr>
		<tr>
			<td bgcolor="#004488">
				<div align="left">
					<font face='verdana'><strong>Password</strong></font>
				</div>
			</td>
			<td bgcolor="#004488">
				<div align="left"><input type="password" name="password" /></div>
			</td>
		</tr>
		<tr>
			<td>
				<div align="left">
					<font face='verdana'></font>
				</div>
			</td>
			<td>
				<div align="left"></div>
			</td>
		</tr>
		<tr>
			<td>
				<div align="left">
					<font face='verdana'><strong>Email Address</strong>
						<font size="2"><br />
							This must be a valid email address, or you will not be able to log in. </font>
					</font>
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
				<div align="left"></div>
			</td>
		</tr>
		<tr>
			<td bgcolor="#004488">
				<div align="left">
					<font face='verdana'><strong>Date of Birth</strong></font>
				</div>
			</td>
			<td bgcolor="#004488">
				<div align="left"><select name="dobday">
						<?php

						for ($x = 1; $x < 32; $x++) {
							echo "<option>$x</option>";
						}

						?>
					</select>
					<select name="dobmonth">
						<option value="1">January</option>
						<option value="2">February</option>
						<option value="3">March</option>
						<option value="4">April</option>
						<option value="5">May</option>
						<option value="6">June</option>
						<option value="7">July</option>
						<option value="8">August</option>
						<option value="9">September</option>
						<option value="10">October</option>
						<option value="11">November</option>
						<option value="12">December</option>
					</select>
					<select name="dobyear">
						<?php

						for ($x = 2023; $x > 1900; $x--) {
							echo "<option>$x</option>";
						}

						?>
					</select>
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
				<div align="left"></div>
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

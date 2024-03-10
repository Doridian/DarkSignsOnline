<?

$rewrite_done = true;

$htmltitle="Create a new account";
require "_top.php";
require_once 'api/mysql_config.php';
global $db;


if (isset($_POST['username'])){
	$username=trim($_POST['username']);
	$password=trim($_POST['password']);
	$email=trim($_POST['email']);
	$dobday=trim($_POST['dobday']);
	$dobmonth=trim($_POST['dobmonth']);
	$dobyear=trim($_POST['dobyear']);

	$username=str_replace(" ","-",trim($username));
	//check if email already exists
	$stmt = $db->prepare("SELECT id from users where email=?");
	$stmt->bind_param('s', $email);
	$stmt->execute();
	if ($stmt->get_result()->num_rows>0){
		die("The email address <b>$email</b> already exists in the database. Please try again.");
	}
	//check if username already exists
	$stmt = $db->prepare("SELECT id from users where username=?");
	$stmt->bind_param('s', $username);
	$stmt->execute();
	if ($stmt->get_result()->num_rows>0){
		die("The username <b>$username</b> already exists in the database. Please try again.");
	}
	if (strstr($username,"_")){die("Error, please don't use underscore characters like _ in your username.");}
	if (strstr($username," ")){die("Error, please don't use space characters in your username.");}
	if (strstr($username,">")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"~")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"!")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"`")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"@")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"#")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"$")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"%")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"^")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"&")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"*")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"<")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"/")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"\\")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"(")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,")")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"_")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"+")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"=")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"[")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"{")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"]")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"}")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"|")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,":")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,";")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"\"")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"'")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,"?")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,",")){die("Error, please don't use invalid characters in your username.");}
	if (strstr($username,".")){die("Error, please don't use invalid characters in your username.");}
	
	
	//check password length
	if (strlen($password)<6){die("Your password should be at least 6 characters long.");}
	//insert the data

	$ctime = date('h:i A');$ctime=str_replace("zz0","","zz".$ctime);$ctime=str_replace("zz","",$ctime);
	$cdate =trim( str_replace(" 0"," "," ".date('dS \of F Y')));
	$ahostname = gethostbyaddr($_SERVER['REMOTE_ADDR']);
	$aip = $_SERVER['REMOTE_ADDR'];
	$vercode=rand(1,1000).rand(1,1000).rand(1,1000).rand(1,1000);
	$timestamp=time();
	
	if (trim(strtolower($dobmonth))=="january"){$dobmonth="1";}if (trim(strtolower($dobmonth))=="february"){$dobmonth="2";}
	if (trim(strtolower($dobmonth))=="march"){$dobmonth="3";}if (trim(strtolower($dobmonth))=="april"){$dobmonth="4";}
	if (trim(strtolower($dobmonth))=="may"){$dobmonth="5";}if (trim(strtolower($dobmonth))=="june"){$dobmonth="6";}
	if (trim(strtolower($dobmonth))=="july"){$dobmonth="7";}if (trim(strtolower($dobmonth))=="august"){$dobmonth="8";}
	if (trim(strtolower($dobmonth))=="september"){$dobmonth="9";}if (trim(strtolower($dobmonth))=="october"){$dobmonth="10";}
	if (trim(strtolower($dobmonth))=="november"){$dobmonth="11";}if (trim(strtolower($dobmonth))=="december"){$dobmonth="12";}
		

	$stmt = $db->prepare("INSERT INTO users (username, password, email, createdate, createtime, ip, hostname, lastseen, enabled, expiredate, dobday, dobmonth, dobyear, tagline, publicemail, timestamp, emailverifycode, emailverified, cash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
	if (!$stmt) {
		echo "Error: ".$stmt->error;
	}
	$one = 1;
	$beta_testing = 'Beta Testing';
	$empty = '';
	$zero = 0;
	$cash = 200;
	$stmt->bind_param('ssssssssisiiissisii', $username, $password, $email, $cdate, $ctime, $aip, $ahostname, $cdate, $one, $beta_testing, $dobday, $dobmonth, $dobyear, $empty, $empty, $timestamp, $vercode, $zero, $cash);
	$stmt->execute();
	$res = $stmt->get_result();
	$userid = $db->insert_id;

	$randomip;
	$res;
	$stmt = $db->prepare("SELECT * FROM iptable WHERE ip=?");
	do
	{
		$randomip = rand(1,255).".".rand(1,255).".".rand(1,255).".".rand(1,255);
		$stmt->bind_param('s', $randomip);
		$stmt->execute();
		$res = $stmt->get_result();
	} while ($res->num_rows != 0);

	$stmt = $db->prepare("INSERT INTO iptable (owner, ip) VALUES (?, ?)");
	$stmt->bind_param('is', $userid, $randomip);
	$stmt->execute();
	$id = $db->insert_id;
	$stmt = $db->prepare("INSERT INTO domain (id, name, ext, time, ip) VALUES (?, ?, ?, ?, ?)");
	$usr = 'usr';
	$stmt->bind_param('issis', $id, $username, $usr, $timestamp, $aip);
	$stmt->execute();

	$headers = "From: Dark Signs Online <do-not-reply@darksignsonline.com>\r\n" ;

	mail($email,"$username, verify your Dark Signs Account","Hi $username,\n\nThank you for creating an account on Dark Signs Online!\n\nClick the link below to activate your account.\n\n$api_path/?verify=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttp://www.darksignsonline.com/","$headers");

	echo "<center><br><br><font size='4' color='orange' face='arial'><b>Your account has been created!</b><br>Check your email address for more information.</font></center>";
	exit;
}

?>

<br />
<font face="Georgia, Times New Roman, Times, serif" size="+3">Create a new account</font><br />
<br />


<form action="create_account.php" method="post">
<table width="546" border="0" cellpadding="10" cellspacing="0" bgcolor="#003366">
  <tr>
    <td width="281"><div align="left"><font face='verdana'><strong>Username</strong><br />
      <font size="2">Try to be unique.<br />
       Do not use spaces, underscores, or other strange characters. You may use dashes. </font></font><br />
    
</div></td>
    <td width="245" ><div align="left"><input type="text" name="username" /></div></td>
  </tr>
  <tr>
    <td bgcolor="#004488"><div align="left"><font face='verdana'><strong>Password</strong></font></div></td>
    <td bgcolor="#004488"><div align="left"><input type="password" name="password" /></div></td>
  </tr>
  <tr>
    <td><div align="left"><font face='verdana'></font></div></td>
    <td><div align="left"></div></td>
  </tr>
  <tr>
    <td><div align="left"><font face='verdana'><strong>Email Address</strong><font size="2"><br />
      This must be a valid email address, or you will not be able to log in. </font></font></div></td>
    <td><div align="left"><input name="email" type="text" size="35" />
    </div></td>
  </tr>
  <tr>
    <td><div align="left"><font face='verdana'></font></div></td>
    <td><div align="left"></div></td>
  </tr>
  <tr>
    <td bgcolor="#004488"><div align="left"><font face='verdana'><strong>Date of Birth</strong></font></div></td>
    <td bgcolor="#004488"><div align="left"><select name="dobday">
	<?
	
		for ($x=1;$x<32;$x++){
			echo "<option>$x</option>";
		}
	
	?>
	</select>
	 <select name="dobmonth">
	<option>January</option>
	<option>February</option>
	<option>March</option>
	<option>April</option>
	<option>May</option>
	<option>June</option>
	<option>July</option>
	<option>August</option>
	<option>September</option>
	<option>October</option>
	<option>November</option>
	<option>December</option>
	</select>
	<select name="dobyear"><?
	
		for ($x=2023;$x>1900;$x--){
			echo "<option>$x</option>";
		}
	
	?></select></div></td>
  </tr>
  <tr>
    <td><div align="left"><font face='verdana'></font></div></td>
    <td><div align="left"></div></td>
  </tr>
  <tr>
    <td><div align="left"><font face='verdana'></font></div></td>
    <td><div align="left"><font face="Verdana" size="1"><strong>By creating an account, you agree to the <a href="termsofuse.php" target="_blank" style="color:#DDE8F9">Dark Signs Online TERMS OF USE</a>.</strong></font><br />
        <br />
        <input type="submit" value="Create the account..." /></div></td>
  </tr>

</table>
</form>
<br />
<br />
<?
require "_bottom.php";

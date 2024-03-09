<?
	$htmltitle="Create a new account";
	include("_top.php");
?>


<?

	if (isset($username)){
		$username=str_replace(" ","-",trim($username));
		//attempt to create the account
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		//check if email already exists
		if (mysql_num_rows(mysql_query("SELECT ind from users where email='$email'"))>0){
			die("The email address <b>$email</b> already exists in the database. Please try again.");
		}
		//check if username already exists
		if (mysql_num_rows(mysql_query("SELECT ind from users where username='$username'"))>0){
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
		

			$ind=mysql_num_rows(mysql_query("SELECT ind from users"))+1;
			$ctime = addslashes(date('h:i A'));$ctime=str_replace("zz0","","zz".$ctime);$ctime=str_replace("zz","",$ctime);
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
			
			$mysql_string="INSERT into users (ind, username, password, email, createdate, createtime, ip, hostname, lastseen, enabled, expiredate, dobday, dobmonth, dobyear, tagline, publicemail, timestamp, emailverifycode, emailverified, cash) VALUES ('$ind', '$username', '$password', '$email', '$cdate', '$ctime', '$aip', '$ahostname', '$cdate', '1', 'Beta Testing', '$dobday', '$dobmonth', '$dobyear', '', '', '$timestamp', '$vercode', '0', '200')";
			
			$dom = "$username.usr";				
			$d=$dom;$d=strtolower($d);   $d=str_replace("http://","",$d);   $d=str_replace("www.","",$d);
			$d=str_replace("!","",$d);$d=str_replace("@","",$d);$d=str_replace("#","",$d);$d=str_replace("$","",$d);
			$d=str_replace("%","",$d);$d=str_replace("^","",$d);$d=str_replace("&","",$d);$d=str_replace("*","",$d);
			$d=str_replace("(","",$d);$d=str_replace(")","",$d);$d=str_replace("_","",$d);$d=str_replace("+","",$d);
			$d=str_replace("=","",$d);$d=str_replace("[","",$d);$d=str_replace("{","",$d);$d=str_replace("}","",$d);
			$d=str_replace("]","",$d);$d=str_replace("\\","",$d);$d=str_replace("|","",$d);$d=str_replace("$","",$d);
			$d=str_replace(":","",$d);$d=str_replace(";","",$d);$d=str_replace("\"","",$d);$d=str_replace("'","",$d);
			$d=str_replace(",","",$d);$d=str_replace("<","",$d);$d=str_replace("/","",$d);$d=str_replace(">","",$d);
			$d=str_replace("?","",$d);$d=str_replace("`","",$d);$d=str_replace("~","",$d);
			$d=trim($d);$dom=$d;
			
			//also register the default domain name
			register_domain($username, $dom);
			
		//echo "$mysql_string<br><br>";
		
		mysql_query($mysql_string)or die(mysql_error());

		
		$headers = "From: Dark Signs Online <do-not-reply@darksigns.com>\r\n" ;
			
		mail("$email","$username, verify your Dark Signs Account","Hi $username,\n\nThank you for creating an account on Dark Signs Online!\n\nClick the link below to activate your account.\n\n$api_path/?verify=$vercode\n\nThank you,\n\nThe Dark Signs Online Team\nhttp://www.darksignsonline.com/","$headers");
		
		echo "<center><br><br><font size='4' color='orange' face='arial'><b>Your account has been created!</b><br>Check your email address for more information.</font></center>";
		
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
	
		for ($x=2002;$x>1900;$x--){
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
include("_bottom.php");
?>
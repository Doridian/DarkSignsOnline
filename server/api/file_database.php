<?

$rewrite_done = true;
require_once('function.php');

$returnwith = (string)(int)$_REQUEST['returnwith'];
if ($returnwith === '0') {
	$returnwith = '2000';
}

echo $returnwith;

$getfile = $_REQUEST['getfile'];
if (!empty($getfile)){
    $stmt = $db->prepare('SELECT * FROM file_database WHERE id = ? AND deleted = 0');
    $stmt->bind_param('i', $getfile);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res->fetch_array();
    if (empty($row)) {
        die_error('File not found.', 404);
    }

    $sid = $row['id'];
    $filedata = $row['filedata'];
    $fname = $row['filename'];
    $fname=str_replace("\\","",$fname);
    $fname=str_replace("/","",$fname);
    
    die("$fname:$filedata");
}


$removenow = $_REQUEST['removenow'];
if (!empty($removenow)){
    $stmt = $db->prepare('UPDATE file_database SET deleted = 1 WHERE id = ? AND author = ?');
    $stmt->bind_param('ii', $removenow, $user['id']);
    $stmt->execute();
    die("File ID $removenow was removed.");
}


$getforremoval = $_REQUEST['getforremoval'];
if (!empty($getforremoval)){
    $stmt = $db->prepare('SELECT * FROM file_database WHERE author = ? AND deleted = 0');
    $stmt->bind_param('i', $user['id']);
    $stmt->execute();
    $res = $stmt->get_result();

    while($row = $res->fetch_array()) {
        $sid = $row['id'];
        $title = $row['title'];
        $version = $row['version'];
        $author = $row['author'];
        $description = $row['description'];
        $cdate = $row['createdate'];								
        $ctime = $row['createtime'];

        echo "$sid: $title (version $version) $cdate:--:";
    }

    exit;
}

$getcategory = $_REQUEST['getcategory'];
if (!empty($getcategory)){
    $stmt = $db->prepare('SELECT * FROM file_database WHERE category = ? AND deleted = 0');
    $stmt->bind_param('s', $getcategory);
    $stmt->execute();
    $res = $stmt->get_result();
    while($row = $res->fetch_array()) {
        $sid = $row['id'];
        $title = $row['title'];
        $version = $row['version'];
        $author = $row['author'];
        $filesize = $row['filesize'];
        $description = $row['description'];
        $cdate = $row['createdate'];								
        $ctime = $row['createtime'];
        $fname = $row['filename'];

        echo $sid.":--:".$title.":--:".$version.":--:".$filesize.":--:".$author.":--:".$fname.":--:".$description.":--:".$cdate.":--:".$ctime.":--:--:";
    }
    exit;
}

$shortfilename = $_REQUEST['shortfilename'];
if (!empty($shortfilename)){
    $timestamp = time();
    $aip = $_SERVER['REMOTE_ADDR'];
    $stmt = $db->prepare('INSERT INTO file_database (filename, version, title, description, createtime, ip, deleted, owner) VALUES (?,?,?,?,?,?,0,?)');
    $stmt->bind_param('ssssis', $shortfilename, $_REQUEST['version'], $_REQUEST['title'], $_REQUEST['description'], $timestamp, $aip, $user['id']);
    $stmt->execute();

    die("Upload complete!");
}

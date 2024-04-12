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
    $stmt = $db->prepare('SELECT * FROM file_database WHERE id = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('ii', $getfile, $ver);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res->fetch_array();
    if (empty($row)) {
        die_error('File not found.', 404);
    }

    echo $row['filename'];
    echo ':';
    die($row['filedata']);
}


$removenow = $_REQUEST['removenow'];
if (!empty($removenow)){
    $stmt = $db->prepare('UPDATE file_database SET deleted = 1 WHERE id = ? AND owner = ? AND ver = ?');
    $stmt->bind_param('iii', $removenow, $user['id'], $ver);
    $stmt->execute();
    die("File ID $removenow was removed.");
}


$getforremoval = $_REQUEST['getforremoval'];
if (!empty($getforremoval)){
    $stmt = $db->prepare('SELECT * FROM file_database WHERE owner = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('ii', $user['id'], $ver);
    $stmt->execute();
    $res = $stmt->get_result();

    while($row = $res->fetch_array()) {
        $sid = $row['id'];
        $title = $row['title'];
        $version = $row['version'];
        $owner = $row['owner'];
        $description = $row['description'];
        $cdate = $row['createdate'];								
        $ctime = $row['createtime'];

        echo "$sid: $title (version $version) $cdate:--:";
    }

    exit;
}

$getcategory = $_REQUEST['getcategory'];
if (!empty($getcategory)){
    $stmt = $db->prepare('SELECT * FROM file_database WHERE category = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('si', $getcategory, $ver);
    $stmt->execute();
    $res = $stmt->get_result();
    while($row = $res->fetch_array()) {
        $sid = $row['id'];
        $title = $row['title'];
        $version = $row['version'];
        $owner = $row['owner'];
        $filesize = $row['filesize'];
        $description = $row['description'];
        $cdate = $row['createdate'];								
        $ctime = $row['createtime'];
        $fname = $row['filename'];

        echo $sid.":--:".$title.":--:".$version.":--:".$filesize.":--:".$owner.":--:".$fname.":--:".$description.":--:".$cdate.":--:".$ctime.":--:--:";
    }
    exit;
}

$shortfilename = $_REQUEST['shortfilename'];
if (!empty($shortfilename)){
    $timestamp = time();
    $aip = $_SERVER['REMOTE_ADDR'];
    $stmt = $db->prepare('INSERT INTO file_database (filename, version, title, description, category, createtime, ip, deleted, owner, ver) VALUES (?,?,?,?,?,?,?,0,?,?)');
    $stmt->bind_param('sssssisii', $shortfilename, $_REQUEST['version'], $_REQUEST['title'], $_REQUEST['description'], $_REQUEST['category'], $timestamp, $aip, $user['id'], $ver);
    $stmt->execute();

    die("Upload complete!");
}

die_error('Invalid request.', 400);

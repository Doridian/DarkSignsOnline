<?php
    require('_top.php');

    function get_release_client($release) {
        foreach (json_decode($release['assets']) AS $asset) {
            if ($asset['name'] !== 'client.zip') {
                continue;
            }
            return $asset;
        }
        return null;
    }

    function get_release_date($release) {
        foreach (json_decode($release['assets']) AS $asset) {
            if ($asset['name'] !== 'client.zip') {
                continue;
            }
            return $asset['updated_at'];
        }
        return 'N/A';
    }
?>
<br /><span class="style5"><br />
    <p><br />
        <font face="Georgia, Times New Roman, Times, serif" size="+3">Download</font><br />
        <br />
        <font face="Verdana" size="2">Make sure you also have an <a href="/create_account.php">account</a> ready.</font>
        <br /><br />
    <table width="60%" border="0">
        <?php
            foreach(json_decode(file_get_contents('releases.json')) AS $release) {
                $client = get_release_client($release);
                if (empty($client)) {
                    continue;
                }
        ?>
        <tr>
            <td width="34%">
                <font face="Verdana" size="2"><strong><?php echo htmlentities($release['name']); ?></strong><br />
                    Updated <?php echo htmlentities($client['updated_at']); ?></font>
            </td>
            <td width="66%">
                <div align="right"><a
                        href="<?php echo htmlentities($asset['browser_download_url']); ?>">Download</a><br /></div>
            </td>
        </tr>
        <?php } ?>
        <tr>
            <td>&nbsp;</td>
            <td>
                <div align="center">
                    <font face="Georgia" size="3"><br />
                        <br />
                    </font>
                </div>
            </td>
        </tr>
    </table>
    <br />
    <br />
    <br />
    </p>
</span>
<?php require('_bottom.php'); ?>

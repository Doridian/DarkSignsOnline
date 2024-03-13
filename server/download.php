<?php
require('_top.php');

function get_release_client($release)
{
    foreach (json_decode($release->assets) as $asset) {
        if ($asset->name !== 'client.zip') {
            continue;
        }
        return $asset;
    }
    return null;
}
?>
<br /><span class="style5"><br />
    <p><br />
        <font face="Georgia, Times New Roman, Times, serif" size="+3">Download</font><br />
        <br />
        <font face="Verdana" size="2">Make sure you also have an <a href="/create_account.php">account</a> ready.</font>
        <br />
    </p>
    <table width="60%" border="0">
        <?php
        foreach (json_decode(file_get_contents('releases.json')) as $release) {
            $client = get_release_client($release);
            if (empty($client)) {
                continue;
            }
            $name = $release->name;
            if ($name === 'main' || $name === 'latest') {
                $name = 'Latest';
            }
        ?>
            <tr>
                <td width="100%">
                    <font face="Verdana" size="2"><strong><?php echo htmlentities($name); ?></strong><br />
                        Updated <?php echo htmlentities($client->updated_at); ?><br />
                        <a href="<?php echo htmlentities($release->tarball_url); ?>">Source code</a></font>
                </td>
                <td>
                    <a href="<?php echo htmlentities($client->browser_download_url); ?>">Download</a>
                </td>
            </tr>
        <?php } ?>
    </table>
    <br />
    <br />
</span>
<?php require('_bottom.php');

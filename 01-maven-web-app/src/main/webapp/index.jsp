<?php
/*
 * index.php
 *
 * Part of wts.com/global
 * Copyright (c) 2024 Dnyaneshwts
 * All rights reserved.
 *
 * Licensed under the MIT License. See the LICENSE file for details.
 */

/*
MIT License

Copyright (c) 2024 Dnyaneshwts

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

require_once("auth.inc");
require_once("util.inc");
require_once("functions.inc");
require_once("captiveportal.inc");

header("Expires: 0");
header("Cache-Control: no-cache, no-store, must-revalidate");
header("Pragma: no-cache");
header("Connection: close");

global $cpzone, $cpzoneid, $cpzoneprefix;

$cpzone = strtolower($_REQUEST['zone']);
$cpcfg = config_get_path("captiveportal/{$cpzone}");

/* NOTE: IE 8/9 is buggy and that is why this is needed */
$orig_request = trim($_REQUEST['redirurl'], " /");

/* If the post-auth redirect is set, always use it. Otherwise take what was supplied in URL. */
if (!empty($cpcfg) && is_URL($cpcfg['redirurl'], true)) {
    $redirurl = $cpcfg['redirurl'];
} elseif (preg_match("/redirurl=(.*)/", $orig_request, $matches)) {
    $redirurl = urldecode($matches[1]);
} elseif ($_REQUEST['redirurl']) {
    $redirurl = $_REQUEST['redirurl'];
}
/* Sanity check: If the redirect target is not a URL, do not attempt to use it like one. */
if (!is_URL(urldecode($redirurl), true)) {
    $redirurl = "";
}

if (empty($cpcfg)) {
    log_error("Submission to captiveportal with unknown parameter zone: " . htmlspecialchars($cpzone));
    portal_reply_page($redirurl, "error", gettext("Internal error"));
    ob_flush();
    return;
}

$cpzoneid = $cpcfg['zoneid'];
$cpzoneprefix = CPPREFIX . $cpzoneid;
$orig_host = $_SERVER['HTTP_HOST'];
$clientip = $_SERVER['REMOTE_ADDR'];

if (!$clientip) {
    /* not good - bail out */
    log_error("Zone: {$cpzone} - Captive portal could not determine client's IP address.");
    $errormsg = gettext("An error occurred.  Please check the system logs for more information.");
    portal_reply_page($redirurl, "error", $errormsg);
    ob_flush();
    return;
}

$ourhostname = portal_hostname_from_client_ip($clientip);
$protocol = (isset($config['captiveportal'][$cpzone]['httpslogin'])) ? 'https://' : 'http://';
$logouturl = "{$protocol}{$ourhostname}/";

$cpsession = captiveportal_isip_logged($clientip);
if (!empty($cpsession)) {
    $sessionid = $cpsession['sessionid'];
}

/* Automatically switching to the logout page requires a custom logout page to be present. */
if ((!empty($cpsession)) && (! $_POST['logout_id']) && (!empty($cpcfg['page']['logouttext']))) {
    /* if client already connected and a custom logout page is set : show logout page */
    $attributes = array();
    if (!empty($cpsession['session_timeout']))
        $attributes['session_timeout'] = $cpsession['session_timeout'];
    if (!empty($cpsession['session_terminate_time']))
        $attributes['session_terminate_time'] = $cpsession['session_terminate_time'];

    include("{$g['varetc_path']}/captiveportal-{$cpzone}-logout.html");
    ob_flush();
    return;
} elseif (!empty($cpsession) && !isset($_POST['logout_id'])) {
    /* If the client tries to access

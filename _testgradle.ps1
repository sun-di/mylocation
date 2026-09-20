$sources = @(
    "https://services.gradle.org/distributions/gradle-9.1.0-all.zip",
    "https://mirrors.aliyun.com/macports/distfiles/gradle/gradle-9.1.0-all.zip",
    "https://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-all.zip",
    "https://mirrors.huaweicloud.com/gradle/gradle-9.1.0-all.zip",
    "https://repo.maven.apache.org/maven2/"
)
foreach ($u in $sources) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($u)
        $req.Method = "HEAD"
        $req.Timeout = 8000
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        Write-Host ("OK   " + $resp.StatusCode + "  " + $u)
        $resp.Close()
    } catch {
        Write-Host ("FAIL " + $_.Exception.Message.Split([Environment]::NewLine)[0] + "  " + $u)
    }
}

# ==============================================================================
# TRASH-GUARD.PS1 — HỆ THỐNG BẢO VỆ CHẶN XÓA CỨNG (POWERSHELL)
# ==============================================================================
# Quy tắc tiên quyết: Tuyệt đối không xóa cứng/vĩnh viễn file hoặc thư mục.
# Bắt buộc chuyển vào thùng rác (Windows Recycle Bin) qua lệnh 'trash'.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function trash {
    <#
    .SYNOPSIS
        Di chuyển an toàn file hoặc thư mục vào Windows Recycle Bin.
    .EXAMPLE
        trash file.txt
        trash -rf folder1 folder2
        Get-ChildItem *.tmp | trash
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Path,

        [Alias('r', 'rf', 'fr')]
        [switch]$Recurse,

        [Alias('f')]
        [switch]$Force
    )

    begin {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    }

    process {
        foreach ($p in $Path) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }

            # Bỏ qua nếu token là flag như -r, -rf, -f, /f, /q, v.v.
            if ($p -match '^[/-]{1,2}[a-zA-Z]+$') { continue }

            $resolvedPaths = @()
            try {
                if (Test-Path -LiteralPath $p) {
                    $resolvedPaths = @((Resolve-Path -LiteralPath $p -ErrorAction Stop).ProviderPath)
                } else {
                    $resolvedPaths = @((Resolve-Path -Path $p -ErrorAction Stop).ProviderPath)
                }
            } catch {
                Write-Error "[Trash] Lỗi: Không tìm thấy file hoặc thư mục: $p"
                continue
            }

            foreach ($fullPath in $resolvedPaths) {
                try {
                    if (Test-Path -LiteralPath $fullPath -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "[Trash] Đã chuyển thư mục vào thùng rác: $fullPath" -ForegroundColor Green
                    } elseif (Test-Path -LiteralPath $fullPath) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "[Trash] Đã chuyển file vào thùng rác: $fullPath" -ForegroundColor Green
                    } else {
                        Write-Warning "[Trash] Đường dẫn không còn tồn tại: $fullPath"
                    }
                } catch {
                    Write-Error "[Trash] Lỗi khi chuyển '$fullPath' vào thùng rác: $_"
                }
            }
        }
    }
}

Set-Alias -Name recycle -Value trash -Option AllScope -Force -ErrorAction SilentlyContinue

function Block-HardDelete {
    param()
    $msg = "[LỖI NGHIÊM TRỌNG] Thao tác xóa cứng bị chặn!`n" +
           "QUY TẮC TIÊN QUYẾT: TUYỆT ĐỐI KHÔNG ĐƯỢC xoá cứng/xoá vĩnh viễn file hoặc thư mục.`n" +
           "BẮT BUỘC phải dùng lệnh di chuyển vào thùng rác (Trash / Recycle Bin).`n" +
           "Vui lòng dùng: trash <đường_dẫn>"
    throw $msg
}

# Override built-in aliases & functions
$blockedCommands = @('Remove-Item', 'rm', 'del', 'erase', 'rd', 'rmdir', 'ri')
foreach ($cmd in $blockedCommands) {
    Remove-Item "alias:$cmd" -Force -ErrorAction SilentlyContinue
    Set-Alias -Name $cmd -Value Block-HardDelete -Scope Global -Option AllScope -Force -ErrorAction SilentlyContinue
}

function global:Remove-Item { Block-HardDelete @args }
function global:rm { Block-HardDelete @args }
function global:del { Block-HardDelete @args }
function global:erase { Block-HardDelete @args }
function global:rd { Block-HardDelete @args }
function global:rmdir { Block-HardDelete @args }
function global:ri { Block-HardDelete @args }

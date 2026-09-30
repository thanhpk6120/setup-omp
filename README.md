# setup-omp

Script bootstrap thiết lập môi trường và cấu hình `.omp` (`mcp.json`, `models.yml`, `config.yml`) cho máy mới, bám sát tài liệu chính thức của từng nhà cung cấp MCP.

## Danh sách MCP Servers & Tài liệu chính thức

1. **memorix**: Tài liệu [AVIDS2/memorix](https://github.com/AVIDS2/memorix)
   - Lệnh: `memorix serve --mode lite`
   - Hook: `memorix setup --agent omp --global` đăng ký plugin `memorix-omp-package` (`extensions/memorix.js`): session_start, before_agent_start, session_before_compact, session_compact, session_shutdown
2. **gitnexus**: Tài liệu [GitNexus Windows MCP](https://github.com/abhigyanpatwari/GitNexus)
   - Bootstrap cài global (`npm i -g gitnexus`) rồi dùng đường dẫn tuyệt đối `cmd /c <abs-path>\gitnexus mcp` để tránh npx cold-cache vượt MCP timeout 30s; fallback `cmd /c npx -y gitnexus@latest mcp`
   - Index trống (`list_repos total=0`) thì chạy: `gitnexus analyze`
3. **company-atlassian**: Tài liệu [mcp-atlassian Installation](https://mcp-atlassian.soomiles.com/docs/installation)
   - Lệnh: `uvx --from mcp-atlassian==0.23.1 mcp-atlassian` (pin version, bỏ cờ `--python 3.12` thừa)
   - Biến môi trường: `JIRA_URL`, `JIRA_PERSONAL_TOKEN`, `CONFLUENCE_URL`, `CONFLUENCE_PERSONAL_TOKEN`, `TOOLSETS`
4. **context7**: Tài liệu [Upstash Context7 MCP](https://github.com/upstash/context7)
   - Lệnh: `cmd /c npx -y @upstash/context7-mcp`
   - Biến môi trường (optional, tăng rate limit): `CONTEXT7_API_KEY` — không có thì chạy anonymous, bootstrap tự bỏ block `env`
5. **cloakbrowser**: Local script `node D:\Thanhpk\AI\cloakbrowser\mcp-server-full.mjs`
   - Bootstrap kiểm tra `Test-Path` trước, máy không có file thì bỏ khỏi `mcp.json` kèm cảnh báo

> Ghi chú: `mcp.json` không còn trường `$schema` vì URL schema cũ trả 404.
## Chạy bootstrap

```powershell
# Chạy cài đặt đầy đủ (yêu cầu Node.js, npm, git)
.\bootstrap.ps1

# Dry-run xem trước thay đổi (không ghi file)
.\bootstrap.ps1 -DryRun

# Bỏ qua bước cài đặt runtime (chỉ tạo file config)
.\bootstrap.ps1 -SkipInstall
```

## Chạy kiểm tra

```powershell
.\test-bootstrap.ps1
```

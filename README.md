# setup-omp

Script bootstrap thiết lập môi trường và cấu hình `.omp` (`mcp.json`, `models.yml`, `config.yml`) cho máy mới, bám sát tài liệu chính thức của từng nhà cung cấp MCP. Default AI Base URL sử dụng `https://openrouter.ai/api/v1`.

## Danh sách MCP Servers & Tài liệu chính thức

1. **memorix**: Tài liệu [AVIDS2/memorix](https://github.com/AVIDS2/memorix)
   - Lệnh: `memorix serve --mode lite`
   - Yêu cầu Node.js >= 22.18.0.
   - Hook: `memorix setup --agent omp --global` đăng ký plugin `memorix-omp-package` (`extensions/memorix.js`): session_start, before_agent_start, session_before_compact, session_compact, session_shutdown
2. **gitnexus**: Tài liệu [GitNexus Windows MCP](https://github.com/abhigyanpatwari/GitNexus)
   - Bootstrap cài global (`npm i -g gitnexus`) rồi dùng đường dẫn tuyệt đối `cmd /c <abs-path>\gitnexus mcp` để tối ưu thời gian khởi động.
   - Yêu cầu Node.js >= 22.18.0. Quá trình bootstrap sẽ tự kiểm tra và báo lỗi nếu chưa đáp ứng hoặc cài lỗi thiếu file.
   - Index trống (`list_repos total=0`) thì chạy: `gitnexus analyze`
3. **company-atlassian**: Tài liệu [mcp-atlassian Installation](https://mcp-atlassian.soomiles.com/docs/installation)
   - Quản lý cài đặt/cập nhật qua `uv`: `uv tool install mcp-atlassian==0.23.1 --upgrade`
   - Lệnh chạy trực tiếp: `mcp-atlassian` (không dùng `uvx --from`)
   - Biến môi trường: `JIRA_URL`, `JIRA_PERSONAL_TOKEN`, `CONFLUENCE_URL`, `CONFLUENCE_PERSONAL_TOKEN`, `TOOLSETS`
4. **context7**: Tài liệu [Upstash Context7 MCP](https://github.com/upstash/context7)
   - Bootstrap cài global (`npm i -g @upstash/context7-mcp`), dùng lệnh `node <npm-root>/@upstash/context7-mcp/dist/index.js`
   - Yêu cầu Node.js >= 22.18.0.
   - Biến môi trường (optional, tăng rate limit): `CONTEXT7_API_KEY` — không có thì chạy anonymous, bootstrap tự bỏ block `env`

5. **cloakbrowser**: Trình duyệt ẩn danh
   - Hỗ trợ quét danh sách ổ đĩa và cho phép chọn vị trí lưu trữ (mặc định D:, C:).
   - Tự động kiểm tra và bảo toàn dữ liệu profile cũ nếu thư mục nguồn và mã nguồn đã tồn tại.
> Ghi chú: `mcp.json` không còn trường `$schema` vì URL schema cũ trả 404.
## Cài đặt nhanh (1 dòng lệnh duy nhất)

Mở PowerShell trên máy mới và chạy:

```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-omp/main/install.ps1 | iex
```

---
## Hợp đồng hành vi & Nguyên tắc (Contract Updates)

Bộ script tuân thủ 7 hợp đồng nguyên tắc:
1. **Evidence loop**: Không giả định kết quả; mọi thao tác cấu hình và tạo file đều có bước xác thực bằng chứng (evidence) qua test thực tế (`test-bootstrap.ps1`) trước khi kết luận hoàn tất.
2. **MCP generic**: Cấu hình file `mcp.json` theo chuẩn generic mcpServers, loại bỏ schema cũ 404, tách biệt rõ ràng giữa config và runtime args.
3. **Cloakbrowser + chọn ổ**: Hỗ trợ CloakBrowser MCP với tính năng quét danh sách ổ đĩa và cho phép chọn ổ đĩa cài đặt (mặc định D:, C:), bảo toàn mã nguồn và profile cũ nếu đã có.
4. **uv mcp-atlassian**: Quản lý cài đặt/cập nhật `mcp-atlassian` qua `uv tool install mcp-atlassian==0.23.1 --upgrade`, chạy trực tiếp bằng command `mcp-atlassian`.
5. **Overwrite (Ghi đè an toàn)**: Không ghi đè các file config cá nhân (`models.yml`, `config.yml`, `mcp.json`) nếu đã tồn tại; luôn ghi đè (`overwrite`) các file quy tắc (`AGENTS.md`, `RULES.md`, `SYSTEM.md`) và thư mục `skills/` để đồng bộ mới nhất.
6. **Reload-context**: Hỗ trợ workflow tải lại ngữ cảnh (`reload-context` / nạp lại rules, skills, agents) ngay sau khi cấu hình/tool cập nhật mà không cần khởi động lại toàn bộ session.
7. **Cleanup skill**: Đồng bộ thư mục `skills/` giúp dọn dẹp các rule và skill lỗi thời hoặc thừa, giữ hệ sinh thái skill tinh gọn và chuẩn xác.

---

## Chạy thủ công từ repo

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
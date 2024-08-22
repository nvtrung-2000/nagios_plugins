# Hướng dẫn sử dụng check_asm_oracle.pl

## Giới thiệu

`check_asm` là một plugin Nagios được thiết kế để kiểm tra trạng thái của Oracle Automatic Storage Management (ASM). Script này có thể kiểm tra nhiều khía cạnh của ASM, bao gồm trạng thái disk group, không gian sử dụng, trạng thái đĩa và lỗi trong alert log.

## Yêu cầu hệ thống

- Perl 5.10 hoặc cao hơn
- Các module Perl sau:
  - DBI
  - DBD::Oracle
  - Cache::FileCache
  - Log::Log4perl
  - Getopt::Long
  - Time::HiRes

## Cài đặt

1. Sao chép script `check_asm` vào thư mục plugins của Nagios (thường là `/usr/lib64/nagios/plugins/`).
2. Cấp quyền thực thi cho script:
   ```
   chmod +x /usr/lib64/nagios/plugins/check_asm_oracle.pl
   ```
3. Cài đặt các module Perl cần thiết. Bạn có thể sử dụng CPAN:
   ```
   cpan DBI DBD::Oracle Cache::FileCache Log::Log4perl
   ```

## Cấu hình

### Cấu hình sudo

1. Chỉnh sửa file `/etc/sudoers` để cho phép người dùng Nagios chạy script với quyền của người dùng Oracle:
   ```
   Defaults:nagios !requiretty
   nagios ALL=(oracle) NOPASSWD: /usr/lib64/nagios/plugins/check_asm
   ```

### Cấu hình Nagios

Thêm các command sau vào file cấu hình Nagios (thường là `commands.cfg`):

```
define command {
    command_name check_asm_diskstatus
    command_line sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ARG1$ --action=diskstatus
}

define command {
    command_name check_asm_dgstate
    command_line sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ARG1$ --action=dgstate
}

define command {
    command_name check_asm_alertlogerror
    command_line sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ARG1$ --action=alertlogerror
}

define command {
    command_name check_asm_usedspace
    command_line sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ARG1$ --action=usedspace --threshold $ARG2$
}
```

## Sử dụng

Cú pháp cơ bản:

```
check_asm --asm_home <ORACLE_HOME for ASM> --action <ACTION> [--threshold <GROUP_DISK=WarnPerc:CritPerc>]
```

### Các tham số

- `--asm_home`: Đường dẫn đến ORACLE_HOME cho instance ASM
- `--action`: Hành động kiểm tra (status|dgstate|diskstatus|usedspace|alertlogerror)
- `--threshold`: Ngưỡng cảnh báo và nguy hiểm cho không gian sử dụng (chỉ dùng với action usedspace)

### Các hành động

1. `status`: Kiểm tra xem instance ASM có đang chạy không
2. `dgstate`: Kiểm tra trạng thái của các disk group
3. `diskstatus`: Kiểm tra trạng thái của các đĩa trong ASM
4. `usedspace`: Kiểm tra không gian sử dụng của các disk group
5. `alertlogerror`: Kiểm tra các lỗi ORA- trong alert log của ASM

### Ví dụ

1. Kiểm tra trạng thái disk:
   ```
   ./check_asm --asm_home=/oracle/gridhome --action=diskstatus
   ```

2. Kiểm tra trạng thái disk group:
   ```
   ./check_asm --asm_home=/oracle/gridhome --action=dgstate
   ```

3. Kiểm tra không gian sử dụng với ngưỡng tùy chỉnh:
   ```
   ./check_asm --asm_home=/oracle/gridhome --action=usedspace --threshold DATA=95:98
   ```

## Xử lý lỗi

Nếu script gặp lỗi, nó sẽ trả về một mã trạng thái và thông báo lỗi phù hợp với chuẩn Nagios. Các log chi tiết được ghi vào file log của Log::Log4perl (mặc định là STDERR).

## Caching

Script sử dụng caching để cải thiện hiệu suất. Kết quả của các kiểm tra được cache trong 5 phút (có thể điều chỉnh bằng cách thay đổi giá trị `CACHE_EXPIRY`).

## Bảo mật

Script này cần quyền truy cập vào instance ASM. Đảm bảo rằng chỉ những người dùng được ủy quyền mới có thể chạy script này.

## Hỗ trợ

Nếu bạn gặp bất kỳ vấn đề nào khi sử dụng script này, vui lòng liên hệ với team hỗ trợ hoặc tạo một issue trên repository của project.
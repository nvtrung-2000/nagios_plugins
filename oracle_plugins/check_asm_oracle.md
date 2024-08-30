# Script check_asm.pl

Script check_asm.pl là một plugin Nagios được viết bằng Perl để giám sát Oracle ASM (Automatic Storage Management). Script này thực hiện các check trạng thái, sức khỏe của ASM instance và các disk group.

## Các thành phần chính

1. Khai báo sử dụng các module Perl cần thiết như DBI, Getopt::Long, Parallel::ForkManager, Cache::FileCache, Log::Log4perl.

2. Định nghĩa các hằng số:
   - DEFAULT_WARN_PERC: Ngưỡng cảnh báo mặc định (85%)
   - DEFAULT_CRIT_PERC: Ngưỡng critical mặc định (95%) 
   - CACHE_EXPIRY: Thời gian cache hết hạn (300s)
   - MAX_PARALLEL_PROCESSES: Số process song song tối đa (5)
   - Các câu lệnh SQL để check trạng thái ASM

3. Xử lý tham số dòng lệnh với Getopt::Long để lấy các tham số:
   - asm_home: đường dẫn ORACLE_HOME của ASM 
   - action: hành động check (status, dgstate, usedspace, diskstatus, alertlogerror)
   - threshold: ngưỡng cảnh báo cho từng diskgroup (chỉ áp dụng cho action usedspace)

4. Kiểm tra xem ASM instance đang chạy hay không, lấy SID và thiết lập các biến môi trường.

5. Kết nối đến ASM instance bằng DBI.

6. Dựa vào tham số action, gọi tới hàm thực hiện check tương ứng:
   - status: check trạng thái ASM instance 
   - dgstate: check trạng thái các disk group
   - usedspace: check dung lượng sử dụng của disk group
   - diskstatus: check trạng thái của các disk trong ASM
   - alertlogerror: check lỗi trong ASM alert log

7. Các hàm check sẽ trả về exit code tương ứng với trạng thái và thông điệp, ví dụ:
   - OK (exit code 0)
   - WARNING (exit code 1)
   - CRITICAL (exit code 2)
   - UNKNOWN (exit code 3)

8. Kết quả check được cache lại trong 1 khoảng thời gian quy định bởi CACHE_EXPIRY.

9. Có validate các tham số đầu vào và hiển thị cách sử dụng nếu tham số không hợp lệ.

## Cách sử dụng

```
$0 --help --asm_home <ORACLE_HOME for ASM> --action <ACTION> --threshold <GROUP_DISK=integer> [[--threshold <GROUP_DISK=integer>] ...]

Examples:
    $0 --asm_home /u01/app/oracle/product/11.2.0/asm --action usedspace --threshold DATA=80:90  
    $0 --asm_home /u01/app/oracle/product/11.2.0/asm --action status

Options:
    --help:         prints this info
    --asm_home:     ORACLE_HOME for asm instance   
    --action:       status|dgstate|diskstatus|usedspace|alertlogerror
    --threshold:    GROUP_DISK_NAME=WarnPerc:CritPerc - percentage threshold for used space (range [0..100]) - use for <usedspace> action
```

## Yêu cầu

- Perl 5.8.3 hoặc cao hơn
- Các module Perl: DBI, DBD::Oracle, Getopt::Long, Parallel::ForkManager, Cache::FileCache, Time::HiRes, Log::Log4perl
- Truy cập vào ASM instance với quyền đọc dba_* views
- Plugin được đặt đúng vị trí trong thư mục libexec của Nagios và có quyền thực thi

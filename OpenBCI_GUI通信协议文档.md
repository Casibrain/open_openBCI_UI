# OpenBCI GUI 硬件通信协议文档

> 版本: v6.0.0-beta.1 | 适用于 Processing 4.5.5 | 最后更新: 2026-07-08

---

## 目录

1. [概述](#1-概述)
2. [串口通信协议（Cyton）](#2-串口通信协议cyton)
3. [无线电台配置协议](#3-无线电台配置协议)
4. [Cyton 命令集](#4-cyton-命令集)
5. [Ganglion 命令集](#5-ganglion-命令集)
6. [WiFi 通信协议](#6-wifi-通信协议)
7. [BLE/蓝牙通信](#7-ble蓝牙通信)
8. [BrainFlow SDK 接口](#8-brainflow-sdk-接口)
9. [LSL 流协议](#9-lsl-流协议)
10. [OSC 协议](#10-osc-协议)
11. [UDP 协议](#11-udp-协议)
12. [串口输出协议](#12-串口输出协议)
13. [键盘命令映射](#13-键盘命令映射)

---

## 1. 概述

OpenBCI GUI 支持多种硬件通信协议，用于连接和控制 OpenBCI 系列 EEG 设备：

| 协议 | 传输层 | 主要用途 |
|------|--------|----------|
| 串口（Cyton） | USB-Serial | Cyton 数据传输与命令控制 |
| 串口（电台） | USB-Serial | 无线电台配置 |
| WiFi | TCP/UDP | Cyton/Ganglion 无线数据传输 |
| WiFi SSDP | UDP 多播 | WiFi 模块发现 |
| BLE（BLED112） | 串口透传 BLE | Ganglion 外部蓝牙适配器 |
| BLE（原生） | 原生 BLE | Ganglion 内置蓝牙 |
| BrainFlow | 内部 SDK | 所有板卡数据抽象层 |
| LSL | TCP | 多应用数据共享 |
| OSC | UDP | 音频/多媒体应用数据流 |
| UDP | UDP | JSON 格式数据流 |

---

## 2. 串口通信协议（Cyton）

### 2.1 连接参数

| 参数 | 值 |
|------|-----|
| 波特率 | `115200` |
| 端口 | 通过控制面板选择 |
| 库 | `processing.serial.Serial` |

### 2.2 串口握手状态机

```
STATE_NOCOM = 0         // 未连接
STATE_COMINIT = 1       // 端口已打开，等待 3000ms 板卡初始化
STATE_SYNCWITHHARDWARE = 2  // 发送 'v' 重置硬件，等待 '$$$'
STATE_NORMAL = 3        // 正常数据流模式
STATE_STOPPED = 4       // 已停止
```

### 2.3 传输结束标记

- **EOT（End of Transmission）**: `$$$`（三个美元符号）
- GUI 在每个命令后等待 `$$$` 才发送下一个命令
- 检测逻辑：`prev3chars[0] == '$' && prev3chars[1] == '$' && prev3chars[2] == '$'`

### 2.4 二进制数据包格式（Cyton 8通道）

```
+----------+----------+---------------------+-------------------+----------+
| Byte 0   | Byte 1   | Bytes 2-25          | Bytes 26-31       | Byte 32  |
| 0xA0     | 包计数器 | 8通道 x 3字节 EEG   | 6字节 AUX 数据    | 0xC0     |
| (起始符) | (1字节)  | (24字节)            | (加速度数据)      | (结束符) |
+----------+----------+---------------------+-------------------+----------+
```

**字段说明：**

| 字段 | 大小 | 说明 |
|------|------|------|
| 起始符 | 1 字节 | 固定值 `0xA0` |
| 包计数器 | 1 字节 | 顺序计数器，0-255 循环 |
| 通道数据 | 24 字节 | 8通道 × 3字节，小端序，24位有符号（ADS1299格式） |
| AUX 数据 | 6 字节 | 3轴 × 2字节（加速度数据） |
| 结束符 | 1 字节 | `0xC0` 或 `0xC1` |

**总计：33 字节/包**

### 2.5 缩放因子

```
ADS1299 参考电压 = 4.5V
ADS1299 增益 = 24.0（默认）
缩放因子（微伏/计数）= Vref / (2^23 - 1) / gain × 1,000,000
加速度缩放因子（G/计数）= 0.002 / (2^4)
阻抗驱动电流 = 6.0e-9 安培
采样率 = 250 Hz（默认）
```

---

## 3. 无线电台配置协议

### 3.1 命令格式

所有命令使用两字节前缀 `0xF0` + 命令字节 + 可选数据字节。

### 3.2 命令列表

| 操作 | 命令字节 | 说明 |
|------|----------|------|
| 获取系统状态 | `0xF0 0x07` | 返回 "Success: System is Up" 或 "Failure: System is Down" |
| 获取频道 | `0xF0 0x00` | 返回当前电台频道 |
| 设置频道 | `0xF0 0x01 <channel>` | 设置电台 + 板卡频道（1-25） |
| 覆盖频道 | `0xF0 0x02 <channel>` | 仅设置电台频道（1-25） |

### 3.3 响应格式

ASCII 文本，以 `$$$` 结尾：
- `"Success: System is Up"` - 系统正常
- `"Failure: System is Down"` - 系统故障
- `"Success: Host override"` - 频道覆盖成功

### 3.4 时序要求

- 发送命令后等待 50-100ms 再读取响应
- 自动扫描：遍历频道 1-25，发送 `0xF0 0x02 <ch>` + `0xF0 0x07` 直到找到成功响应

---

## 4. Cyton 命令集

所有命令通过 `boardShim.config_board(command)` 发送，由 BrainFlow SDK 转发到板卡固件。

### 4.1 板卡模式命令

| 命令 | 模式 | 说明 |
|------|------|------|
| `/0` | DEFAULT | 默认模式（加速度计开启） |
| `/1` | DEBUG | 调试模式 |
| `/2` | ANALOG | 模拟模式 |
| `/3` | DIGITAL | 数字模式 |
| `/4` | MARKER | 标记模式 |

### 4.2 ADS1299 通道设置命令

**格式：** `x<通道><功率><增益><输入类型><偏置><SRB2><SRB1>X`

**通道选择器：** `1,2,3,4,5,6,7,8,Q,W,E,R,T,Y,U,I`（前8个为Cyton，后8个为Daisy）

| 参数 | 选项 | 说明 |
|------|------|------|
| 功率 | 0=ON, 1=OFF | 通道开关 |
| 增益 | 0=X1, 1=X2, 2=X4, 3=X6, 4=X8, 5=X12, 6=X24 | 放大倍数 |
| 输入类型 | 0=NORMAL, 1=SHORTED, 2=BIAS_MEAS, 3=MVDD, 4=TEMP, 5=TEST, 6=BIAS_DRP, 7=BIAS_DRN | 输入源 |
| 偏置 | 0=NO_INCLUDE, 1=INCLUDE | 偏置包含 |
| SRB2 | 0=DISCONNECT, 1=CONNECT | SRB2连接 |
| SRB1 | 0=DISCONNECT, 1=CONNECT | SRB1连接 |

**示例：** `x10100001X` = 通道1, 功率ON, 增益X1, 正常输入, 无偏置, SRB2断开, SRB1连接

### 4.3 阻抗检测命令

**格式：** `z<通道><p><n>Z`

| 参数 | 说明 |
|------|------|
| 通道 | 同上（1-8, Q-I） |
| p | '1'=检测正极引脚, '0'=不检测 |
| n | '1'=检测负极引脚, '0'=不检测 |

**示例：** `z410Z` = 检测通道4正极阻抗

### 4.4 Daisy 管理命令

| 命令 | 说明 | 返回值 |
|------|------|--------|
| `c` | 检测 Daisy | "daisy removed"（已连接时） |
| `C` | 连接 Daisy | "no daisy to attach"（无Daisy时） |

### 4.5 SD 卡录制命令

| 命令 | 最大录制时间 |
|------|--------------|
| `A` | 5 分钟 |
| `S` | 15 分钟 |
| `F` | 30 分钟 |
| `G` | 1 小时 |
| `H` | 2 小时 |
| `J` | 4 小时 |
| `K` | 12 小时 |
| `L` | 24 小时 |
| `j` | 关闭 SD 文件 |

### 4.6 其他命令

| 命令 | 说明 |
|------|------|
| `v` | 重置硬件（串口初始化同步时发送） |
| `?` | 打印寄存器 |
| `d` | 重置板卡为默认值（阻抗检测时发送，BrainFlow 预连接时自动发送） |
| `[` | 启用合成方波 |
| `]` | 禁用合成方波 |

### 4.7 采样率命令（WiFi模式）

| 采样率 (Hz) | 命令 |
|-------------|------|
| 16000 | `~0` |
| 8000 | `~1` |
| 4000 | `~2` |
| 2000 | `~3` |
| 1000 | `~4` |
| 500 | `~5` |
| 250 | `~6` |

---

## 5. Ganglion 命令集

### 5.1 通道激活/停用命令

| 通道 | 停用 | 激活 |
|------|------|------|
| 1 | `1` | `!` |
| 2 | `2` | `@` |
| 3 | `3` | `#` |
| 4 | `4` | `$` |
| 5 | `5` | `%` |
| 6 | `6` | `^` |
| 7 | `7` | `&` |
| 8 | `8` | `*` |
| 9 | `q` | `Q` |
| 10 | `w` | `W` |
| 11 | `e` | `E` |
| 12 | `r` | `R` |
| 13 | `t` | `T` |
| 14 | `y` | `Y` |
| 15 | `u` | `U` |
| 16 | `i` | `I` |

### 5.2 加速度计控制

| 命令 | 说明 |
|------|------|
| `n` | 启用加速度计 |
| `N` | 禁用加速度计 |

### 5.3 阻抗检测

| 命令 | 说明 |
|------|------|
| `z` | 启动阻抗检测模式 |
| `Z` | 停止阻抗检测模式 |

### 5.4 合成方波

| 命令 | 说明 |
|------|------|
| `[` | 启用方波 |
| `]` | 禁用方波 |

### 5.5 采样率命令（Ganglion WiFi）

| 采样率 (Hz) | 命令 |
|-------------|------|
| 25600 | `~0` |
| 12800 | `~1` |
| 6400 | `~2` |
| 3200 | `~3` |
| 1600 | `~4` |
| 800 | `~5` |
| 400 | `~6` |
| 200 | `~7` |

---

## 6. WiFi 通信协议

### 6.1 WiFi 发现（SSDP）

| 参数 | 值 |
|------|-----|
| 协议 | SSDP（简单服务发现协议） |
| 库 | `com.vmichalak.protocol.ssdp.SSDPClient` |
| 发现查询 | `SSDPClient.discover(3000, "urn:schemas-upnp-org:device:Basic:1")` |
| 超时 | 3000ms |

### 6.2 WiFi 连接参数

| 参数 | 值 |
|------|-----|
| IP 端口 | `6677`（Cyton 和 Ganglion 相同） |
| 默认 IP | `192.168.4.1`（AP 模式） |

### 6.3 WiFi IP 地址模式

- **动态模式：** 通过 SSDP 自动发现（显示设备名 + IP）
- **静态模式：** 用户手动输入 IP 地址

### 6.4 BrainFlow WiFi 板卡 ID

```
BoardIds.CYTON_WIFI_BOARD
BoardIds.CYTON_DAISY_WIFI_BOARD
BoardIds.GANGLION_WIFI_BOARD
```

---

## 7. BLE/蓝牙通信

### 7.1 板卡变体

```
BoardIds.GANGLION_BOARD         -> BLED112 BLE 适配器（外部）
BoardIds.GANGLION_NATIVE_BOARD  -> 原生蓝牙（内置）
```

### 7.2 Ganglion BLE 参数

| 参数 | 说明 |
|------|------|
| 串口 | BLED112 适配器所需 |
| MAC 地址 | 设备标识必需 |
| 板卡名称格式 | `"Ganglion X.X"`（如 `"Ganglion 1.3"`） |

### 7.3 固件版本检测

| 固件版本 | 板卡名称特征 | 丢包追踪器 |
|----------|--------------|------------|
| v2 | 不包含 "Ganglion 1.3" | `PacketLossTrackerGanglionBLE2` |
| v3 | 包含 "Ganglion 1.3" | `PacketLossTrackerGanglionBLE3` |

### 7.4 丢包追踪参数

- **加速度开启时采样索引范围：** 0-200
- **加速度关闭时采样索引范围：** 根据配置变化

---

## 8. BrainFlow SDK 接口

### 8.1 连接初始化

```java
boardShim = new BoardShim(boardId, params);
boardShim.prepare_session();
boardShim.start_stream(450000, brainflowStreamer);  // 缓冲区: 450000 采样点
```

### 8.2 流式传输板卡（远程数据）

| 参数 | 说明 |
|------|------|
| BoardIds | `STREAMING_BOARD` |
| ip_address | 远程 IP 地址 |
| ip_port | 远程端口 |
| master_board | 主板卡 ID |

### 8.3 BrainFlow Streamer 格式

```
文件流：  "file://filename.txt"
目录流：  "file://folder"
```

### 8.4 数据获取 API

```java
double[][] data = boardShim.get_board_data();  // 获取所有新数据
boardShim.insert_marker(value);                // 插入标记
```

### 8.5 通道元数据 API

| 方法 | 返回内容 |
|------|----------|
| `get_eeg_channels(boardId)` | EEG 通道索引 |
| `get_emg_channels(boardId)` | EMG 通道索引 |
| `get_ecg_channels(boardId)` | ECG 通道索引 |
| `get_accel_channels(boardId)` | 加速度通道索引 |
| `get_other_channels(boardId)` | 其他通道索引 |
| `get_marker_channel(boardId)` | 标记通道索引 |
| `get_sampling_rate(boardId)` | 采样率 |
| `get_package_num_channel(boardId)` | 包号通道 |
| `get_timestamp_channel(boardId)` | 时间戳通道 |
| `get_num_rows(boardId)` | 总通道数 |

---

## 9. LSL 流协议

### 9.1 LSL 流创建

```java
LSL.StreamInfo info = new LSL.StreamInfo(
    streamName,       // 流名称，如 "obci_eeg1"
    streamType,       // 流类型，如 "EEG"
    numChannels,      // 通道数
    sampleRate,       // 采样率
    LSL.ChannelFormat.float32,
    "openbcigui"      // stream_id
);
LSL.StreamOutlet outlet = new LSL.StreamOutlet(info);
```

### 9.2 默认 LSL 流名称

| 流编号 | 名称 | 类型 |
|--------|------|------|
| 1 | `obci_eeg1` | EEG |
| 2 | `obci_eeg2` | EEG |
| 3 | `obci_eeg3` | EEG |

### 9.3 LSL 通道数（按数据类型）

| 数据类型 | 通道数 |
|----------|--------|
| TimeSeries（原始/滤波） | EXG 通道数 |
| Focus | 1 |
| FFT | 125 |
| EMG | EXG 通道数 |
| AvgBandPower | 5 |
| BandPower | 6（通道号 + 5频带） |
| Pulse | 2（BPM, IBI） |
| Accel/Aux | 3（x, y, z） |
| EMGJoystick | 2（x, y） |
| Marker | 1 |

---

## 10. OSC 协议

### 10.1 OSC 连接

```java
OscP5 osc = new OscP5(this, port + 1000);  // 监听端口 = 发送端口 + 1000
NetAddress oscNetAddress = new NetAddress(ip, port);
OscMessage msg = new OscMessage("/openbci");  // 基础地址
```

### 10.2 OSC 地址模式

基础地址：`/openbci`

| 数据类型 | 地址模式 |
|----------|----------|
| TimeSeries 原始 | `/openbci/time-series-raw/ch<chNum>` |
| TimeSeries 滤波 | `/openbci/time-series-filtered/ch<chNum>` |
| FFT | `/openbci/fft/ch<chNum>/bin<binNum>` |
| 频带功率 | `/openbci/band-power/<channel>` |
| 平均频带功率 | `/openbci/average-band-power/<band>` |
| EMG | `/openbci/emg/<channel>` |
| 加速度 X | `/openbci/accelerometer/x` |
| 加速度 Y | `/openbci/accelerometer/y` |
| 加速度 Z | `/openbci/accelerometer/z` |
| 模拟输入 | `/openbci/analog/<channel>` |
| 数字输入 | `/openbci/digital/<channel>` |
| 脉搏 BPM | `/openbci/pulse/bpm` |
| 脉搏 IBI | `/openbci/pulse/ibi` |
| EMG 摇杆 | `/openbci/emg-joystick/x`, `/openbci/emg-joystick/y` |
| 专注度 | `/openbci/focus` |
| 标记 | `/openbci/marker` |

### 10.3 默认 OSC 端口

```
流 1: 127.0.0.1:12345
流 2: 127.0.0.1:12346
流 3: 127.0.0.1:12347
流 4: 127.0.0.1:12348
```

---

## 11. UDP 协议

### 11.1 UDP 出站（数据流）

```java
UDP udp = new UDP(this);
udp.setBuffer(20000);
udp.listen(false);
udp.send(dataString, ip, port);
```

### 11.2 UDP 数据格式（JSON）

所有 UDP 数据为 JSON 格式，以 `\r\n` 结尾：

```json
{"type":"<type>","data":[...]}\r\n
```

| 数据类型 | JSON type 字段 | 数据结构 |
|----------|----------------|----------|
| TimeSeriesRaw | `timeSeriesRaw` | `[[ch1_samples...],[ch2_samples...],...]` |
| TimeSeriesFilt | `timeSeriesFilt` | `[[ch1_samples...],[ch2_samples...],...]` |
| FFT | `fft` | `[[bin0..bin124 for ch0],[bin0..bin124 for ch1],...]` |
| BandPower | `bandPower` | `[[delta,theta,alpha,beta,gamma for ch0],...]` |
| AvgBandPower | `averageBandPower` | `[delta,theta,alpha,beta,gamma]` |
| EMG | `emg` | `[norm_ch0,norm_ch1,...]` |
| Accel | `accelerometer` | `[[x_samples...],[y_samples...],[z_samples...]]` |
| Analog | `analog` | `[[ch0_samples...],[ch1_samples...],...]` |
| Digital | `digital` | `[[ch0_values...],[ch1_values...],...]` |
| Pulse | `pulse` | `[bpm, ibi]` |
| Focus | `focus` | `0` 或 `1` |
| EMGJoystick | `emgJoystick` | `[x, y]` |
| Marker | `marker` | `[markerValue1,markerValue2,...]` |

### 11.3 默认 UDP 端口

```
流 1: 127.0.0.1:12345
流 2: 127.0.0.1:12346
流 3: 127.0.0.1:12347
```

### 11.4 UDP 标记接收器（入站）

```java
UDP udpReceiver = new UDP(ourApplet, markerReceivePort, markerReceiveIP);
udpReceiver.listen(true);
udpReceiver.setReceiveHandler("receiveMarkerViaUdp");
```

| 参数 | 默认值 |
|------|--------|
| 监听 IP | `127.0.0.1` |
| 监听端口 | `12350` |
| 数据格式 | 4字节 IEEE 754 浮点数（小端序） |

---

## 12. 串口输出协议

### 12.1 连接参数

```java
serial_networking = new processing.serial.Serial(pApplet, portName, baudRate);
```

### 12.2 支持的波特率

```
57600, 115200, 250000, 500000
```

### 12.3 数据格式

| 数据类型 | 格式示例 |
|----------|----------|
| Time Series | `[ch1_val,ch2_val,...,chN_val]`（每通道3位小数） |
| BandPower | `[chanNum,delta,theta,alpha,beta,gamma]` |
| AvgBandPower | `[delta,theta,alpha,beta,gamma]` |
| EMG | `val1,val2,...\n` |
| Pulse | `bpm,ibi` |
| EMG Joystick | `+x.xx,y.yy\n` |
| Focus | `0\n` 或 `1\n` |
| Marker | `markerValue\n` |
| Accelerometer | `[+x.x,..][+y.y,..][+z.z,..]` |

**注意：** FFT 的串口输出已禁用（数据量过大），会自动切换为 BandPower 输出。

---

## 13. 键盘命令映射

| 按键 | 功能 |
|------|------|
| `Space` | 开始/停止数据流 |
| `1-8` | 停用通道 1-8 |
| `!@#$%^&*` | 激活通道 1-8 |
| `q w e r t y u i` | 停用通道 9-16 |
| `Q W E R T Y U I` | 激活通道 9-16 |
| `[` | 启用合成方波 |
| `]` | 禁用合成方波 |
| `n` | 保存用户设置 |
| `N` | 加载用户设置 |
| `?` | 打印寄存器（仅 Cyton） |
| `m` | 截图 |
| `,` | 切换容器显示 |
| `z, x, c, v` | 插入标记 1-4 |
| `Z, X, C, V` | 插入标记 5-8 |

---

## 附录 A：协议对照表

| 协议 | 传输层 | 波特率/端口 | 方向 | 主要用途 |
|------|--------|-------------|------|----------|
| 串口（Cyton） | USB-Serial | 115200 | 双向 | Cyton 数据 + 命令 |
| 串口（电台） | USB-Serial | 115200 | 双向 | 电台配置（0xF0前缀） |
| 串口（输出） | USB-Serial | 57600-500000 | 出站 | 向外部应用流式传输数据 |
| WiFi | TCP/UDP | 6677 | 双向 | Cyton/Ganglion 数据 |
| WiFi SSDP | UDP 多播 | - | 入站 | WiFi 模块发现 |
| BLE（BLED112） | 串口透传 | - | 双向 | Ganglion 外部适配器 |
| BLE（原生） | 原生 BLE | - | 双向 | Ganglion 内置蓝牙 |
| BrainFlow | 内部 SDK | - | 内部 | 所有板卡数据抽象 |
| BrainFlow Streaming | TCP/UDP | 可配置 | 入站 | 远程 BrainFlow 数据 |
| LSL | TCP | - | 出站 | 多应用数据共享 |
| OSC | UDP | 可配置（+1000监听） | 出站 | 音频/多媒体应用 |
| UDP（出站） | UDP | 可配置 | 出站 | JSON 数据流 |
| UDP（入站） | UDP | 12350 | 入站 | 外部标记注入 |

---

## 附录 B：数据缩放因子参考

| 参数 | 值 | 说明 |
|------|-----|------|
| ADS1299 参考电压 | 4.5V | ADC 参考电压 |
| 默认增益 | 24x | 可配置 1x-24x |
| 微伏/计数 | Vref / (2^23-1) / gain × 10^6 | EEG 数据转换 |
| 加速度 G/计数 | 0.002 / 2^4 | 加速度数据转换 |
| 阻抗驱动电流 | 6.0 nA | 用于阻抗测量 |
| 默认采样率 | 250 Hz | Cyton 默认 |

---

*本文档基于 OpenBCI GUI v6.0.0-beta.1 源代码生成*

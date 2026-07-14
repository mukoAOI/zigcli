//! Windows ICMP implementation for the ping example.

const std = @import("std");
const Io = std.Io;
const windows = std.os.windows;

pub const EchoParams = struct {
    host: []const u8,
    count: u32,
    timeout_ms: u32,
    interval_ms: u32,
    size: u32,
    verbose: bool,
};

const WSADATA = extern struct {
    wVersion: u16,
    wHighVersion: u16,
    iMaxSockets: u16,
    iMaxUdpDg: u16,
    lpVendorInfo: ?[*:0]u8,
    szDescription: [257]u8,
    szSystemStatus: [129]u8,
};

const ADDRINFOA = extern struct {
    ai_flags: i32,
    ai_family: i32,
    ai_socktype: i32,
    ai_protocol: i32,
    ai_addrlen: usize,
    ai_canonname: ?[*:0]u8,
    ai_addr: ?*windows.ws2_32.sockaddr,
    ai_next: ?*ADDRINFOA,
};

const IP_OPTION_INFORMATION = extern struct {
    Ttl: u8,
    Tos: u8,
    Flags: u8,
    OptionsSize: u8,
    OptionsData: ?*u8,
};

const ICMP_ECHO_REPLY = extern struct {
    Address: u32,
    Status: u32,
    RoundTripTime: u32,
    DataSize: u16,
    Reserved: u16,
    Data: ?*anyopaque,
    Options: IP_OPTION_INFORMATION,
};

extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSADATA) callconv(.winapi) i32;
extern "ws2_32" fn WSACleanup() callconv(.winapi) i32;
extern "ws2_32" fn getaddrinfo(
    pNodeName: ?[*:0]const u8,
    pServiceName: ?[*:0]const u8,
    pHints: ?*const ADDRINFOA,
    ppResult: *?*ADDRINFOA,
) callconv(.winapi) i32;
extern "ws2_32" fn freeaddrinfo(pAddrInfo: ?*ADDRINFOA) callconv(.winapi) void;

extern "iphlpapi" fn IcmpCreateFile() callconv(.winapi) windows.HANDLE;
extern "iphlpapi" fn IcmpCloseHandle(icmp_handle: windows.HANDLE) callconv(.winapi) windows.BOOL;
extern "iphlpapi" fn IcmpSendEcho(
    icmp_handle: windows.HANDLE,
    destination_address: u32,
    request_data: ?*const anyopaque,
    request_size: u16,
    request_options: ?*IP_OPTION_INFORMATION,
    reply_buffer: *anyopaque,
    reply_size: u32,
    timeout: u32,
) callconv(.winapi) u32;

extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

var wsa_started: bool = false;

pub fn run(params: EchoParams) !void {
    try windowsNetStart();
    defer windowsNetCleanup();

    const dest = try resolveIpv4(params.host);
    std.debug.print("PING {s} ({d}.{d}.{d}.{d}) {d} bytes of data.\n", .{
        params.host,
        dest[0],
        dest[1],
        dest[2],
        dest[3],
        params.size,
    });

    var sent: u32 = 0;
    var recv: u32 = 0;
    var rtt_total: u64 = 0;
    var rtt_min: u32 = std.math.maxInt(u32);
    var rtt_max: u32 = 0;

    var i: u32 = 0;
    while (i < params.count) : (i += 1) {
        sent += 1;
        const result = windowsIcmpEcho(dest, params.size, params.timeout_ms) catch |err| {
            std.debug.print("Request timed out. ({s})\n", .{@errorName(err)});
            if (i + 1 < params.count) Sleep(params.interval_ms);
            continue;
        };
        recv += 1;
        rtt_total += result.rtt_ms;
        rtt_min = @min(rtt_min, result.rtt_ms);
        rtt_max = @max(rtt_max, result.rtt_ms);
        std.debug.print("Reply from {d}.{d}.{d}.{d}: bytes={d} time={d}ms TTL={d}\n", .{
            result.from[0],
            result.from[1],
            result.from[2],
            result.from[3],
            result.bytes,
            result.rtt_ms,
            result.ttl,
        });
        if (params.verbose) {
            std.debug.print("  seq={d} status=0x{x}\n", .{ i + 1, result.status });
        }
        if (i + 1 < params.count) Sleep(params.interval_ms);
    }

    const loss: u32 = if (sent == 0) 0 else ((sent - recv) * 100) / sent;
    std.debug.print("\n--- {s} ping statistics ---\n", .{params.host});
    std.debug.print("{d} packets transmitted, {d} received, {d}% packet loss\n", .{ sent, recv, loss });
    if (recv > 0) {
        const avg = rtt_total / recv;
        std.debug.print("rtt min/avg/max = {d}/{d}/{d} ms\n", .{ rtt_min, avg, rtt_max });
    }
}

fn resolveIpv4(host: []const u8) ![4]u8 {
    if (Io.net.Ip4Address.parse(host, 0)) |ip4| {
        return ip4.bytes;
    } else |_| {}
    return try windowsResolveIpv4(host);
}

fn windowsNetStart() !void {
    var data: WSADATA = undefined;
    const ver: u16 = 0x0202;
    if (WSAStartup(ver, &data) != 0) return error.WsaStartupFailed;
    wsa_started = true;
}

fn windowsNetCleanup() void {
    if (wsa_started) {
        _ = WSACleanup();
        wsa_started = false;
    }
}

fn windowsResolveIpv4(host: []const u8) ![4]u8 {
    var host_z_buf: [256]u8 = undefined;
    if (host.len >= host_z_buf.len) return error.NameTooLong;
    @memcpy(host_z_buf[0..host.len], host);
    host_z_buf[host.len] = 0;
    const host_z: [:0]const u8 = host_z_buf[0..host.len :0];

    const hints = ADDRINFOA{
        .ai_flags = 0,
        .ai_family = windows.ws2_32.AF.INET,
        .ai_socktype = windows.ws2_32.SOCK.DGRAM,
        .ai_protocol = 0,
        .ai_addrlen = 0,
        .ai_canonname = null,
        .ai_addr = null,
        .ai_next = null,
    };
    var result: ?*ADDRINFOA = null;
    const rc = getaddrinfo(host_z.ptr, null, &hints, &result);
    if (rc != 0) return error.UnknownHost;
    defer freeaddrinfo(result);

    var it = result;
    while (it) |ai| : (it = ai.ai_next) {
        if (ai.ai_family != windows.ws2_32.AF.INET) continue;
        const sa: *const windows.ws2_32.sockaddr.in = @ptrCast(@alignCast(ai.ai_addr orelse continue));
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, sa.addr, .big);
        return bytes;
    }
    return error.NoIpv4Address;
}

const EchoResult = struct {
    from: [4]u8,
    bytes: u16,
    rtt_ms: u32,
    ttl: u8,
    status: u32,
};

fn windowsIcmpEcho(dest: [4]u8, size: u32, timeout_ms: u32) !EchoResult {
    const handle = IcmpCreateFile();
    if (handle == windows.INVALID_HANDLE_VALUE) return error.IcmpCreateFailed;
    defer _ = IcmpCloseHandle(handle);

    const dest_addr = std.mem.readInt(u32, &dest, .big);

    var payload: [65535]u8 = undefined;
    const n: u16 = @intCast(size);
    @memset(payload[0..n], 0x61);

    const reply_size: u32 = @as(u32, @sizeOf(ICMP_ECHO_REPLY)) + n + 8;
    var reply_buf: [65535 + 128]u8 align(@alignOf(ICMP_ECHO_REPLY)) = undefined;
    if (reply_size > reply_buf.len) return error.ReplyTooLarge;

    const replies = IcmpSendEcho(
        handle,
        dest_addr,
        &payload,
        n,
        null,
        &reply_buf,
        reply_size,
        timeout_ms,
    );
    if (replies == 0) return error.IcmpTimeout;

    const reply: *const ICMP_ECHO_REPLY = @ptrCast(@alignCast(&reply_buf));
    if (reply.Status != 0) return error.IcmpError;

    var from: [4]u8 = undefined;
    std.mem.writeInt(u32, &from, reply.Address, .big);

    return .{
        .from = from,
        .bytes = reply.DataSize,
        .rtt_ms = reply.RoundTripTime,
        .ttl = reply.Options.Ttl,
        .status = reply.Status,
    };
}

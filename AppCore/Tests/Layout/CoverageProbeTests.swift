// TEMPORARY: prints AppCore's zero-count lines at exit. Deleted before the phase's last commit.

#if os(Linux)
    import Foundation
    import Glibc
    import Testing

    @_silgen_name("__llvm_profile_set_filename")
    private func profileSetFilename(_ name: UnsafePointer<CChar>)

    @_silgen_name("__llvm_profile_write_file")
    private func profileWriteFile() -> Int32

    private func dumpCoverage() {
        "/tmp/p5probe.profraw".withCString { profileSetFilename($0) }
        _ = profileWriteFile()
        let exe = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? ""
        let script = """
            TC=$(dirname "$(readlink -f "$(command -v swift)")")
            "$TC/llvm-profdata" merge -sparse /tmp/p5probe.profraw -o /tmp/p5probe.profdata
            "$TC/llvm-cov" show '\(exe)' -instr-profile /tmp/p5probe.profdata -show-line-counts \
              | awk '/^\\/.*\\.swift:$/ { f = $0; next } \
                     f ~ /AppCore\\/Sources\\// && $2 ~ /^ *0$/ { print "PROBE-LINE", f, $0 }' FS='|'
            "$TC/llvm-cov" export '\(exe)' -instr-profile /tmp/p5probe.profdata \
              | python3 -c 'import json,sys
            for e in json.load(sys.stdin)["data"][0]["files"]:
                if "AppCore/Sources/" in e["filename"]:
                    for s in e["segments"]:
                        if s[3] and s[2] == 0 and not s[5]:
                            print("PROBE-SEG", e["filename"].split("AppCore/Sources/")[-1], s[0], s[1], s[4])'
            echo PROBE-DONE
            """
        print("PROBE-START")
        fflush(stdout)
        _ = system(script)
        fflush(stdout)
    }

    @Suite("Coverage probe")
    struct CoverageProbeTests {
        @Test("Registers the exit-time coverage dump")
        func register() {
            atexit { dumpCoverage() }
        }
    }
#endif

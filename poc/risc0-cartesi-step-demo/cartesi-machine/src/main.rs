// counter.rs — Cartesi guest workload-under-proof.
//
// Trivial RISC-V Linux binary that increments a counter `ITERATIONS` times and
// prints the final value. Inside the Cartesi machine this consumes a
// deterministic number of mcycles, giving us a well-defined target for the
// RISC0 step prover in Demo B.
//
// Build (host):
//     rustup target add riscv64gc-unknown-linux-gnu
//     cargo build --release --target riscv64gc-unknown-linux-gnu
// Result: target/riscv64gc-unknown-linux-gnu/release/counter
//
// The build script (scripts/02-build-machine.sh) does this for you.

const ITERATIONS: u64 = 100_000;

fn main() {
    // Use volatile-style updates so the optimiser cannot fold the whole loop
    // into a constant. We want the machine to *actually execute* mcycles.
    let mut counter: u64 = 0;
    let mut acc: u64 = 0xdead_beef;
    for i in 0..ITERATIONS {
        counter = counter.wrapping_add(1);
        // Cheap mixing keeps the loop body non-trivial without blowing up time.
        acc = acc.wrapping_mul(0x100000001b3).wrapping_add(i);
        std::hint::black_box(&counter);
        std::hint::black_box(&acc);
    }
    println!("counter={counter} mixed={acc:#x}");
}

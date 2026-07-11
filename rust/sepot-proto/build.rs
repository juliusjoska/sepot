fn main() -> std::io::Result<()> {
    println!("cargo:rerun-if-changed=../../proto/sepot.proto");
    prost_build::compile_protos(&["../../proto/sepot.proto"], &["../../proto"])
}

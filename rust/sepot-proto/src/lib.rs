//! Wire typy Šepotu generované z `proto/sepot.proto` (jediný zdroj pravdy).

pub mod v1 {
    include!(concat!(env!("OUT_DIR"), "/sepot.v1.rs"));
}

pub use prost::Message;

/// Tvrdý limit velikosti payload obálky (message_queue CHECK).
pub const MAX_ENVELOPE_PAYLOAD: usize = 256 * 1024;

/// Doménový separátor podpisu AUTH výzvy.
pub const AUTH_CONTEXT: &[u8] = b"sepot-auth-v1";

#[cfg(test)]
mod tests {
    use super::v1::*;
    use prost::Message;

    #[test]
    fn envelope_roundtrip() {
        let env = Envelope {
            dst_address: vec![7u8; 32],
            msg_uuid: vec![1u8; 16],
            content_hint: ContentHint::Default as i32,
            payload: vec![0xAB; 128],
        };
        let bytes = env.encode_to_vec();
        let back = Envelope::decode(bytes.as_slice()).unwrap();
        assert_eq!(env, back);
    }

    #[test]
    fn client_frame_oneof() {
        let frame = ClientFrame {
            frame: Some(client_frame::Frame::Ack(Ack {
                msg_uuid: vec![9u8; 16],
            })),
        };
        let bytes = frame.encode_to_vec();
        let back = ClientFrame::decode(bytes.as_slice()).unwrap();
        assert_eq!(frame, back);
    }
}

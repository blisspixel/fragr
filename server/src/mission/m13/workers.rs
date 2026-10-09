//! One release, three authored answers. None of them gates the freight lift.
use crate::protocol::USE_DISTANCE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Response {
    Volunteered,
    DepartedIndependently,
    DeclinedAndKeptWorking,
}

pub const RESPONSES: [Response; 3] = [
    Response::Volunteered,
    Response::DepartedIndependently,
    Response::DeclinedAndKeptWorking,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refuse {
    Inactive,
    AlreadyReleased,
    ThreatsRemain,
    NotCleared,
    TooFar,
}

pub fn try_release(
    active: bool,
    quarters_clear: bool,
    threats_remain: bool,
    already: bool,
    distance: f32,
) -> Result<[Response; 3], Refuse> {
    if !active {
        return Err(Refuse::Inactive);
    }
    if already {
        return Err(Refuse::AlreadyReleased);
    }
    if threats_remain {
        return Err(Refuse::ThreatsRemain);
    }
    if !quarters_clear {
        return Err(Refuse::NotCleared);
    }
    if !(0.0..=USE_DISTANCE).contains(&distance) {
        return Err(Refuse::TooFar);
    }
    Ok(RESPONSES)
}

pub fn gates_exit(responses: [Response; 3]) -> bool {
    let _ = responses;
    false
}

pub fn distance(feet: [f32; 3], approach: [f32; 3]) -> f32 {
    let delta = [
        feet[0] - approach[0],
        feet[1] - approach[1],
        feet[2] - approach[2],
    ];
    delta.iter().map(|value| value * value).sum::<f32>().sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn release_is_once_after_the_fight_and_never_an_exit_key() {
        assert_eq!(
            try_release(false, true, false, false, 1.0),
            Err(Refuse::Inactive)
        );
        assert_eq!(
            try_release(true, true, false, true, 1.0),
            Err(Refuse::AlreadyReleased)
        );
        assert_eq!(
            try_release(true, false, true, false, 1.0),
            Err(Refuse::ThreatsRemain)
        );
        assert_eq!(
            try_release(true, false, false, false, 1.0),
            Err(Refuse::NotCleared)
        );
        assert_eq!(
            try_release(true, true, false, false, USE_DISTANCE + 0.01),
            Err(Refuse::TooFar)
        );
        assert_eq!(
            try_release(true, true, false, false, f32::NAN),
            Err(Refuse::TooFar)
        );
        assert_eq!(
            try_release(true, true, false, false, USE_DISTANCE),
            Ok(RESPONSES)
        );
        assert!(!gates_exit(RESPONSES));
        assert!(RESPONSES.contains(&Response::DeclinedAndKeptWorking));
        assert!(RESPONSES.contains(&Response::DepartedIndependently));
        assert!(RESPONSES.contains(&Response::Volunteered));
    }
}

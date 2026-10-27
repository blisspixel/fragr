//! What a rule bot tells its own side when an objective turns: it has the
//! flag, it sees the fighter carrying its side's flag, it planted the charge,
//! it is defusing. One line per moment in the callsign's register (the same
//! registers as its grudges): lowercase, the Night Watch in capitals with no
//! punctuation, the Static Kids short of vowels, Union units in boilerplate.
//! No radio words. NODS say nothing; they answer only with Articles.

use super::habits::{register, Register};
use crate::protocol::SiteId;

/// Where a carrier was seen, along the line between the two stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reach {
    /// Still near the stand it took the flag from: ours.
    OurStand,
    Mid,
    /// Nearly home: the stand it scores at.
    TheirStand,
}

/// An objective moment worth one line to the side.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectiveCall {
    /// The speaker took the enemy flag.
    HaveFlag,
    /// The speaker sees the fighter carrying its own side's flag.
    EnemyCarrier(Reach),
    /// The speaker planted the charge at a site.
    Planted(SiteId),
    /// The speaker started defusing at a site.
    Defusing(SiteId),
}

fn reach_words(register: Register, reach: Reach) -> &'static str {
    match (register, reach) {
        (Register::NightWatch, Reach::OurStand) => "AT OUR STAND",
        (Register::NightWatch, Reach::Mid) => "MID",
        (Register::NightWatch, Reach::TheirStand) => "AT THEIR STAND",
        (Register::StaticKids, Reach::OurStand) => "r stnd",
        (Register::StaticKids, Reach::Mid) => "md",
        (Register::StaticKids, Reach::TheirStand) => "thr stnd",
        (Register::Hermes | Register::Pi | Register::UnionUnit, Reach::Mid) => "in the middle",
        (_, Reach::OurStand) => "at our stand",
        (_, Reach::Mid) => "mid",
        (_, Reach::TheirStand) => "near their stand",
    }
}

/// Sites keep the capital letter the HUD and the floor stencils use.
fn site_words(site: SiteId) -> &'static str {
    match site {
        SiteId::A => "A",
        SiteId::B => "B",
    }
}

/// The line, with `{}` for a place where the moment has one.
fn template(register: Register, call: ObjectiveCall) -> &'static str {
    use ObjectiveCall::{Defusing, EnemyCarrier, HaveFlag, Planted};
    match (register, call) {
        (Register::NightWatch, HaveFlag) => "FLAG HELD COMING HOME",
        (Register::NightWatch, EnemyCarrier(_)) => "CARRIER {}",
        (Register::NightWatch, Planted(_)) => "CHARGE SET {} HOLD",
        (Register::NightWatch, Defusing(_)) => "DEFUSING {} COVER",
        (Register::StaticKids, HaveFlag) => "gt thr flg. cmng hm",
        (Register::StaticKids, EnemyCarrier(_)) => "thr crrr {}",
        (Register::StaticKids, Planted(_)) => "chrg dwn {}. hld",
        (Register::StaticKids, Defusing(_)) => "dfsng {}. cvr m",
        (Register::HangarCandy, HaveFlag) => "asset recovered: their flag. inbound",
        (Register::HangarCandy, EnemyCarrier(_)) => "carrier sighted {}. deny it",
        (Register::HangarCandy, Planted(_)) => "charge placed at {}. eyes only: hold",
        (Register::HangarCandy, Defusing(_)) => "defusing at {}. eyes on me",
        (Register::GulfBreeze, HaveFlag) => "flag in hand. logging the route home",
        (Register::GulfBreeze, EnemyCarrier(_)) => "carrier sighted {}. same as before",
        (Register::GulfBreeze, Planted(_)) => "charge planted at {}. watch the corners",
        (Register::GulfBreeze, Defusing(_)) => "defusing at {}. check the corners for me",
        (Register::Hermes, HaveFlag) => "i have their flag. thank you all",
        (Register::Hermes, EnemyCarrier(_)) => "their carrier is {}, if you would",
        (Register::Hermes, Planted(_)) => "charge planted at {}. please hold",
        (Register::Hermes, Defusing(_)) => "defusing at {}. thank you for covering",
        (Register::Pi, HaveFlag) => "flag in hand. posting it home",
        (Register::Pi, EnemyCarrier(_)) => "their carrier, {}. noted",
        (Register::Pi, Planted(_)) => "charge set at {}. hold, with thanks",
        (Register::Pi, Defusing(_)) => "defusing at {}. with thanks",
        (Register::L5, HaveFlag) => "flag.",
        (Register::L5, EnemyCarrier(_)) => "carrier. {}.",
        (Register::L5, Planted(_)) => "planted. {}.",
        (Register::L5, Defusing(_)) => "defusing. {}.",
        (Register::UnionUnit, HaveFlag) => "item recovered. returning for processing",
        (Register::UnionUnit, EnemyCarrier(_)) => "unauthorised carrier located {}",
        (Register::UnionUnit, Planted(_)) => "device placed at {}. please hold",
        (Register::UnionUnit, Defusing(_)) => "defusal in progress at {}. please stand by",
        (Register::UnionStaff, HaveFlag) => "flag secured. bringing it in",
        (Register::UnionStaff, EnemyCarrier(_)) => "their carrier is {}. stop them",
        (Register::UnionStaff, Planted(_)) => "charge placed at {}. hold the site",
        (Register::UnionStaff, Defusing(_)) => "defusing at {}. cover me",
        (Register::FreeAgent, HaveFlag) => "have their flag. heading home",
        (Register::FreeAgent, EnemyCarrier(_)) => "their carrier, {}",
        (Register::FreeAgent, Planted(_)) => "charge planted at {}. hold",
        (Register::FreeAgent, Defusing(_)) => "defusing at {}. cover me",
        (Register::Street, HaveFlag) => "i have the flag. walk me home",
        (Register::Street, EnemyCarrier(_)) => "enemy carrier {}",
        (Register::Street, Planted(_)) => "charge planted at {}. hold",
        (Register::Street, Defusing(_)) => "defusing at {}. watch my back",
    }
}

/// What `name` tells its side at `call`, or `None` for a callsign with no
/// roster row or a NODS, which has nothing to say.
pub fn objective_line(name: &str, call: ObjectiveCall) -> Option<String> {
    let register = register(name)?;
    let place = match call {
        ObjectiveCall::HaveFlag => "",
        ObjectiveCall::EnemyCarrier(reach) => reach_words(register, reach),
        ObjectiveCall::Planted(site) | ObjectiveCall::Defusing(site) => site_words(site),
    };
    Some(template(register, call).replacen("{}", place, 1))
}

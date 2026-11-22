// Planted bad input for control verus-strip-failing-test (ci-controls.toml):
// a failing test that the CI Test step must report.
#[test]
fn planted_failure() {
    panic!("planted failure: the Test step must go red");
}

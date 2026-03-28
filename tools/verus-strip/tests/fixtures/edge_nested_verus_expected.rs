//! Edge case: nested braces in ensures clauses.
pub enum MyResult<T, E> {
    Ok(T),
    Err(E),
}
pub struct Semaphore {
    count: u32,
    limit: u32,
}
impl Semaphore {
    pub fn init(count: u32, limit: u32) -> MyResult<Self, i32> {
        if limit == 0 || count > limit {
            MyResult::Err(-1i32)
        } else {
            MyResult::Ok(Semaphore { count, limit })
        }
    }
    pub fn get_count(&self) -> u32 {
        self.count
    }
}

//! Edge case: nested braces in ensures clauses.

use vstd::prelude::*;

verus! {

pub enum MyResult<T, E> {
    Ok(T),
    Err(E),
}

pub struct Semaphore {
    count: u32,
    limit: u32,
}

impl Semaphore {
    pub open spec fn inv(&self) -> bool {
        &&& self.limit > 0
        &&& self.count <= self.limit
    }

    pub fn init(count: u32, limit: u32) -> (result: MyResult<Self, i32>)
        ensures
            match result {
                MyResult::Ok(sem) => {
                    &&& sem.inv()
                    &&& sem.count == count
                },
                MyResult::Err(e) => {
                    &&& e == -1i32
                },
            },
    {
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

} // verus!

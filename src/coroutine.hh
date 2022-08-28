#ifndef coroutine_hh_INCLUDED
#define coroutine_hh_INCLUDED

#include "safe_ptr.hh"

#include <concepts>
#include <coroutine>
#include <exception>
#include <iterator>

namespace Kakoune
{

template<typename T>
class Generator : public SafeCountable
{
public:
    struct promise_type;
    using Handle = std::coroutine_handle<promise_type>;

    Generator(Handle handle) : m_handle(std::move(handle)) {}
    ~Generator() { kak_assert(m_handle.done()); m_handle.destroy(); }
    Generator(const Generator&) = delete;
    Generator& operator=(const Generator&) = delete;
    Generator(Generator&&) = default;
    Generator& operator=(Generator&&) = default;

    struct promise_type
    {
        T value;
        std::exception_ptr exception;

        Generator get_return_object() { return Generator(Handle::from_promise(*this)); }
        std::suspend_always initial_suspend() { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }
        void unhandled_exception() { exception = std::current_exception(); }

        template<std::convertible_to<T> From>
        std::suspend_always yield_value(From &&from) { value = std::forward<From>(from); return {}; }
        void return_void() {}
    };

    class iterator
    {
    public:
        using value_type = T;
        using difference_type = std::ptrdiff_t;
        using pointer = T*;
        using reference = T&;
        using iterator_category = std::input_iterator_tag;

        iterator() = default;
        iterator(Generator<T>& generator) : m_generator(&generator) { ++(*this); }

        iterator& operator++()
        {
            m_generator->m_handle();
            if (auto exception = m_generator->m_handle.promise().exception)
                std::rethrow_exception(exception);
            return *this;
        }
        T&& operator*() const noexcept
        {
            return std::move(m_generator->m_handle.promise().value);
        }
        bool operator==(const iterator& rhs) const
        {
            kak_assert(not rhs.m_generator);
            return m_generator->m_handle.done();
        }
    private:
         SafePtr<Generator<T>> m_generator;
    };

    iterator begin() { return {*this}; }
    iterator end() { return {}; }

private:
    Handle m_handle;
};

}

#endif // coroutine_hh_INCLUDED

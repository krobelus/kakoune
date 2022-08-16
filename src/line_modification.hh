#ifndef line_change_watcher_hh_INCLUDED
#define line_change_watcher_hh_INCLUDED

#include "array_view.hh"
#include "units.hh"
#include "utils.hh"
#include "range.hh"
#include "vector.hh"

namespace Kakoune
{

class Buffer;

struct LineModification
{
    LineCount old_line; // line position in the old buffer
    LineCount new_line; // new line position
    LineCount num_removed; // number of lines removed (including this one)
    LineCount num_added; // number of lines added (including this one)

    LineCount diff() const { return new_line - old_line + num_added - num_removed; }
};

Vector<LineModification> compute_line_modifications(const Buffer& buffer, size_t timestamp);

using LineRange = Range<LineCount>;

using LineRangeList = Vector<LineRange, MemoryDomain::Highlight>;

struct LineRangeSet : private LineRangeList
{
    using Base = LineRangeList;
    using Base::operator[];
    using Base::begin;
    using Base::end;

    ConstArrayView<LineRange> view() const { return {data(), data() + size()}; }

    void reset(LineRange range) { Base::operator=({range}); }

    void update(ConstArrayView<LineModification> modifs);
    LineRangeList add_range(LineRange range);
    void remove_range(LineRange range);
};


}

#endif // line_change_watcher_hh_INCLUDED

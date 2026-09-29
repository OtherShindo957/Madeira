#pragma once
/* The pinned FEX fork uses VirtualQuery in its CASPAL error logger even in
 * the Apple build. This Madeira-owned compatibility header does not implement
 * Windows memory semantics: it reports that diagnostic data is unavailable.
 * It is not used by the atomic emulation itself. No FEX sources are changed.
 */
#ifdef __APPLE__
#include <cstddef>
#include <cstdint>
using LPCVOID = const void *;
struct MEMORY_BASIC_INFORMATION {
  void *BaseAddress{};
  std::size_t RegionSize{};
  std::uint32_t Protect{};
  std::uint32_t Type{};
  std::uint32_t State{};
};
inline constexpr std::uint32_t MEM_IMAGE = 0x1000000;
inline constexpr std::uint32_t MEM_MAPPED = 0x40000;
inline std::size_t VirtualQuery(LPCVOID, MEMORY_BASIC_INFORMATION *, std::size_t) {
  return 0;
}
#endif

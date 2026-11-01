class MapFilterSelection {
  final String? species;
  final String? color;
  final DateTime? from;
  final DateTime? to;

  const MapFilterSelection({this.species, this.color, this.from, this.to});

  int get count =>
      (species == null ? 0 : 1) +
      (color == null ? 0 : 1) +
      (from == null && to == null ? 0 : 1);

  // Dates are calendar days in Bogotá, as parsed by reportDateTimeInBogota.
  bool matches({String? species, String? color, DateTime? date}) {
    String? normalize(String? value) => value?.trim().toLowerCase();
    if (this.species != null && normalize(species) != normalize(this.species)) {
      return false;
    }
    if (this.color != null && normalize(color) != normalize(this.color)) {
      return false;
    }
    if (from == null && to == null) return true;
    if (date == null) return false;
    DateTime day(DateTime value) =>
        DateTime.utc(value.year, value.month, value.day);
    return (from == null || !day(date).isBefore(day(from!))) &&
        (to == null || !day(date).isAfter(day(to!)));
  }
}

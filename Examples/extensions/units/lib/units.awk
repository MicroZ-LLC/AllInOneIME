# The units both commands know: name, kind, and how many base units one is (temperatures are converted by
# formula). `list` prints the table; otherwise the input ("10 km") is converted to the other units of its kind.

BEGIN {
  add("m", "length", 1); add("km", "length", 1000); add("cm", "length", 0.01); add("mi", "length", 1609.344)
  add("ft", "length", 0.3048); add("in", "length", 0.0254)
  add("kg", "weight", 1); add("g", "weight", 0.001); add("lb", "weight", 0.45359237); add("oz", "weight", 0.028349523125)
  add("c", "temperature", 0); add("f", "temperature", 0); add("k", "temperature", 0)
}

function add(name, kind, factor) { names[++count] = name; kinds[name] = kind; factors[name] = factor }

function to_base(value, unit) {
  if (unit == "c") return value; if (unit == "f") return (value - 32) * 5 / 9; if (unit == "k") return value - 273.15
  return value * factors[unit]
}

function from_base(value, unit) {
  if (unit == "c") return value; if (unit == "f") return value * 9 / 5 + 32; if (unit == "k") return value + 273.15
  return value / factors[unit]
}

{
  if ($1 == "list") { for (i = 1; i <= count; i++) printf "%-4s %s\n", names[i], kinds[names[i]]; exit }
  value = $1; unit = tolower($2)
  if (value !~ /^-?[0-9.]+$/ || !(unit in kinds)) {
    printf "{\"items\": [{\"title\": \"Type an amount and a unit, like 10 km\", \"subtitle\": \"km m cm mi ft in · kg g lb oz · c f k\", \"valid\": false}]}\n"
    exit
  }
  base = to_base(value, unit); items = ""
  for (i = 1; i <= count; i++) {
    other = names[i]
    if (other == unit || kinds[other] != kinds[unit]) continue
    result = sprintf("%." precision "f %s", from_base(base, other), other)
    items = items sprintf("%s{\"title\": \"%s\", \"subtitle\": \"%s %s = %s\", \"arg\": \"%s\"}", items == "" ? "" : ",", result, value, unit, result, result)
  }
  printf "{\"items\": [%s]}\n", items
}

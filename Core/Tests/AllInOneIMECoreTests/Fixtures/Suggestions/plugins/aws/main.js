// AWS account ids, each with the name the user knows it by: a row only once all 12 digits are typed. The list is
// the plugin's own (no host to reach); a real one would read it from a preference.

function load(ctx) {
  return { items: [
    { match: "123456789012", title: "prod", variables: { alias: "prod" } },
    { match: "111122223333", title: "staging", variables: { alias: "staging" } },
    { match: "444455556666", title: "sandbox", variables: { alias: "sandbox" } }
  ] };
}

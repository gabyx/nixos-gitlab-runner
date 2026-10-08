{ ... }:
{
  users.users.alice = {
    isNormalUser = true;
    description = "Alice Foobar";
    password = "foobar";
    uid = 1001;
  };

  users.users.bob = {
    isNormalUser = true;
    description = "Bob Foobar";
    password = "foobar";
  };
}

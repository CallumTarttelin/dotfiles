let
  nixshark = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCu9okERT0vR0J7nxGxe/cDr+z9c15894792dSbXQGjfA7E4ETq7hpjL4/WgTAsAPYSoD/+q/l9QaSQ7bmxcBnbCqqpj5cAbY8/86rcV14cCtMHWS1iyKTxvV8et6jMJL1dzu1Ujex1/J2TSHbqjnLGC2xHzLKjNgwHAKhZklLCXWyhmMM9XLD+ZSj2NEwzTzH8SpzbASJFBRYu+SmQ90U9xBb8A1dhwjU0PbWEEMlUmkBAIfFS3wPHbm7+rBdABk4n7kQ8RX2ESlwELHDmplckUnK4QS6bkftgGyWihb3gJOH/W+qH8lP44B9ERjf/sxS4lPgpOAgi2BSZDD6ueS8x7MjKNizkcCGWOBtFlS5loy6y+mYLn0hLNRvQVeaWheqz516pjiPif9SyUyi0gmSp5T35fHynRsQrts7aH8a6422gfsw3hsBCdbOOhqr7MpQZVOotsOBqeaMzYy+ENARBfOo08p8ujePWv934IIEZEkJYS6aClXNtAmfCAMrNs3E= root@nixos";
  allKeys = [nixshark];
in {
  "tarttelin.age".publicKeys = allKeys;
  "root.age".publicKeys = allKeys;
  "borgrepo.age".publicKeys = allKeys;
  "borgpass.age".publicKeys = allKeys;
}

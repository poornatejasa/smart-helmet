const int vibration = A0;

void setup() {
  Serial.begin(9600);
}

void loop() {
  int value = analogRead(vibration);
  Serial.println(value);
  delay(100);
}
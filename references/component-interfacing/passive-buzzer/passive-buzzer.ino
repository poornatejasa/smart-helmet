const int buzzer = 8;

void setup() {}

void loop() {
  for (int freq = 0; freq <= 2000; freq += 10) {
    tone(buzzer, freq);
    delay(10);
  }
  noTone(buzzer);
  delay(500);
}
#define ALCOHOL_PIN A3

void setup() {
  Serial.begin(9600);
  while (!Serial);
  pinMode(ALCOHOL_PIN, INPUT);

}

void loop() {
  Serial.print("Alcohol Value : ");
  Serial.println(analogRead(ALCOHOL_PIN));
  delay(500);
}

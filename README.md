# Guardify
A swift app designed to keep on-campus students safe anytime, anywhere. It leverages AI to provide real-time notifications, mental health support, incident reporting, and navigation assistance. With features like emergency alerts, a campus map, and a safety walk map, it ensures students stay informed and secure.

The alert system can be activated using 1234. The recording starts when the user says 1234, and AI analyzes the conversation. If the threat is detected, it sends an alert message to people with GPS locations. If a conversation detects gun or bomb violence, everyone with the app within 3 miles will be alerted. This AI isn't easy to trick.

The live camera density monitoring uses live streaming videos from CCTV cameras around the campus and shows the density of people around the campus. They can navigate through the app to different parts of campus at night. The app will take them through the safest and quickest route to their desired locations. The camera tracking can also be activated if the user wants to.

The AI chatbot is designed for people to have conversation about their problems and find optimal solution and support.

The Campus Hero system has a mobile app and a central dashboard for Public Safety using AWS services. The tech stack includes:

Backend: Python/Flask,
Frontend: Swift Mobile, ReactJS
AI Technologies: LLM Integration (Claude 3 Hakku, Open Router - Llama 3), OpenCV
AWS Services: Amazon Elastic Container Services, Amazon Elastic Container Registry, Amazon Kinesis, AWS Bedrock

curl https://apihub.agnes-ai.com/v1/responses \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "agnes-2.5-flash",
    "input": [
      {
        "role": "user",
        "content": [
          {
            "type": "input_text",
            "text": "Explain how autonomous agents use tools."
          }
        ]
      }
    ],
    "max_output_tokens": 1024
  }'

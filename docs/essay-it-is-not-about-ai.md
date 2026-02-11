# The Problem Isn't AI — It's Finding What We Already Know

## The Problem

I've been trying to get people to adopt AI. It hasn't been working. After some reflection, I think I've been asking the wrong question. The issue isn't "how do we get people to use AI?" — it's "how do we help people find what they already know?" That reframing changes everything.

Think about the daily frustrations: Where was that procedure documented? What did we try last run? Who figured this out before? Our institutional knowledge exists, but it's scattered across Confluence pages, electronic logbooks, code repositories, and people's heads. The bottleneck isn't intelligence. It's access.

## The Realization

Meanwhile, there's a lot of excitement about AI. Some people in our community are paying for their own subscriptions — using ChatGPT, Claude, or Copilot. But these are generic tools trained on generic data. They don't know our beamline configurations, haven't read our logbooks, can't navigate our codebase.

This is starting to change. Our organization will soon provide Claude API access, and we're already using Stanford AI Gateway APIs for security and compliance. But access alone doesn't solve the knowledge problem — it just gives us a faster way to search the internet. The real value is connecting AI to what we uniquely have: decades of technical documents, terabytes of scientific data, years of electronic logbook entries, and a living codebase that evolves with every experiment.

## The Opportunity

What if, instead of asking people to adopt AI, we simply made our information accessible — and let AI be the interface?

The value proposition shifts entirely. We're not selling "AI adoption." We're offering faster answers. A scientist shouldn't need to know whether they're using a vector database, a semantic search, or a large language model. They should just be able to ask: *"What was the detector configuration for the last successful run on this sample type?"* — and get an answer in seconds instead of hours.

When the underlying knowledge is organized and queryable, AI becomes genuinely useful. Not as a novelty, but as a multiplier. The models are commodities; everyone has access to the same GPT or Claude. But the data — our Confluence pages, our elog entries, our lcls2 codebase, our run catalogs — that's the differentiator.

This approach might also drive AI adoption organically. When people see that AI can actually answer their domain-specific questions because we've done the work to connect it to real knowledge sources, skepticism fades. The value becomes self-evident.

## Next Steps

To move this forward, the focus is on making the skill-building process teachable. We've already built several working examples: code indexing for repositories like lcls2 and smalldata_tools, Confluence documentation export, electronic logbook integration, and connections to our run catalog.

Some of these are easily teachable — users can clone a public repo, run an indexing script, and have a queryable codebase in minutes. Others require centralized maintenance due to API credentials or large datasets. But the pattern is repeatable: identify a knowledge source, structure it for retrieval, and expose it through a simple interface.

The goal isn't to make everyone an AI expert. It's to make institutional knowledge as accessible as a Google search — and let AI handle the last mile of turning retrieval into understanding.

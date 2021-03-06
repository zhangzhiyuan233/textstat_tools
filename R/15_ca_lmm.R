
library(tidyverse)
library(quanteda)
library(spacyr)
library(FactoMineR)
library(factoextra)

spacy_initialize(model = "en")

# The first part of this script illustrates correspondence analysis.
# Correspondence analysis is a descriptive/exploratory technique designed 
# to analyze simple two-way and multi-way tables containing some measure of 
# correspondence between the rows and columns. The results provide information 
# which is similar in nature to those produced by Factor Analysis techniques, 
# and they allow you to explore the structure of categorical variables included in the table.
#
# We're going to start with Brezina's discussion of correspondence analysis
# (pg. 199-206). So first, we'll load in the data that he uses from
# the BNC64 corpus -- a corpus of transcribed spoken British English.
# The data contains counts of 3 speech events from 4 speakers.
bnc <- read_csv("http://corpora.lancs.ac.uk/stats/data/correspondence_analysis.csv")

# If we look at the data, we see the first column contains the names
# of the files, followed by 9 columns of pos categories, with last being
# a sum of less frequent features binned together as "other".
# Keep this in mind as we're going to recreate this set-up with some other data.
head(bnc)

# To execute the correspondence analysis, we'll need to move the "File"
# column to row names.
bnc <- bnc %>% column_to_rownames("File")

# We'll use the CA() function for the correspondence analysis.
# Also note that quanteda has it's own CA functionality.
bnc_ca <- CA(bnc, graph = FALSE)

# On pg. 202, Brezina notes that CA is conceptually related to the
# chi-squared test (pg. 108-116). This appears at the top of the report 
# generated by the function summary().
summary(bnc_ca)

# Recall that  eigenvalues and the proportion of variances retained by the different 
# axes (pg. 166). They can be extracted using the function get_eigenvalue() 
# from the factoextra package. Eigenvalues are larger for the first and 
# second axes and smaller for the rest.
get_eigenvalue(bnc_ca)

# As Brezina notes, it is conventional to report CA results using a biblot,
# which shows both the column and the row categories of the cross-tabulation.
# Generating one is easy using the fviz_ca_biplot() function.
fviz_ca_biplot(bnc_ca, repel = TRUE)

##
# Compare to Brezina pg. 201.
# What does the plot suggest about individual speaker variation?
# For guidance, refer to pg. 202.
##

# We're going to replicate Brezina's example with different data.
# For our experiment, we'll use the Santa Barbara Corpus of Spoken American English:
# https://www.linguistics.ucsb.edu/research/santa-barbara-corpus
# First, we'll read in the metadata. Note, there's a fair amount of demographic data.
sbc_meta <- read_csv("data/meta_data/sbc_meta.csv")

# Now, we'll subset out only those speakers for whom we have data from
# multiple conversations.
sbc_sub <- sbc_meta %>% 
  group_by(id) %>% 
  filter(n()>1)

# It's not a lot. There's only data from 3 speakers over seven converstions.
head(sbc_sub)

# We'll read in the csv files using the file_path column.
sbc_text <- lapply(sbc_sub$file_path, read_csv)

# And well bind our list of data.frames into 1.
sbc_text <- sbc_text %>% bind_rows() %>% ungroup()

# Look at the result. Note that these are conversations with speakers other
# than the 7 that we want. We want to drop the data from other speakers.
head(sbc_text)

# There are a variety of ways of doing this. We'll use a simple one.
# We'll simply filter on a matching vector.
sbc_text <- sbc_text %>% filter(speaker %in% sbc_sub$speaker)

# Check the result...
unique(sbc_text$speaker)

# Let's take another look at our data.
head(sbc_text)

# The structure of spoken language is VERY different from that written langauge.
# This should be evident just by skimming a few lines.
# The data also contains noverbal data and non-transcribable data,
# which are enclosed in angle brackets. The transcriptions also record
# moments where speakers start to produce and sound and stop.
# These are transcripted with a hyphen (like "d-").
# We're going to pos tag this data, so we want to omit these from our tokens
# as they'll cause the tagger difficulty.
#
# We can do this with str_replace_all()..
sbc_text <- sbc_text %>% mutate(text = str_replace_all(text, "<\\S+>", "")) %>%
 mutate(text = str_replace_all(text, " \\w-", ""))

# By doing this we've created some empty rows. So we can filter those out
# by dropping those rows that doing have an a-z character in them.
sbc_text <- sbc_text %>% filter(str_count(text, regex("[a-z]", ignore_case = T)) > 0)

# Check the result...
head(sbc_text)

# Now we're going to collapse all the rows by speaker. We started with
# meta data containing 7 rows (1 for each speaker). After doing this,
# the result should be the same length. Note that we're also renaming
# the "speaker" column to make it easy to read into quanteda.
sbc_text <- sbc_text %>%
  group_by(speaker) %>%
  summarise(text=paste(text,collapse = " ")) %>%
  rename(doc_id = speaker)

# Now we read the result into a cropus...
sbc_corpus <- corpus(sbc_text)

# Parse it...
sbc_prsd <- spacy_parse(sbc_corpus, pos = TRUE, tag = TRUE, entity = FALSE)

# Remove spaces and punctuation... as we're replicating Brezina's data.
sbc_prsd <- sbc_prsd  %>% filter(pos != "SPACE") %>% 
  filter(pos != "PUNCT")

# Split our data.frame into a list...
sbc_tokens <- split(sbc_prsd$pos, sbc_prsd$doc_id)

# And make it a tokens class object...
sbc_tokens <- as.tokens(sbc_tokens)

# In Brezina's data, he used a sample of 1000 tokens for each speaker.
# Let's look to see how many we have...
lapply(sbc_tokens, length)

# Hmmm... Only Pete (in conversation 3) and Cam (in conversation 44)
# have samples of at least 1000 tokens. So we'll have to do things a little differently.
#
# First, we'll make our dfm...
sbc_dfm <- dfm(sbc_tokens)

# And convert it to a data.frame...
sbc_dfm <- convert(sbc_dfm, to = "data.frame")

# Remeber how Brezina's BNC64 was organized into a table of 9 variables plus
# the file name. We're going to have to do a little wrangling to get ours
# in the same format.
# First, we create a new column called "other" that sums the tags that are not
# named in Brezina's data. Then, we drop the orginial columns that we summed.
# And finally, we re-order the columns so the mirror Brezina's.
sbc_dfm <- sbc_dfm %>% 
  rowwise() %>% 
  mutate(other = sum(intj, num, part, propn, x, na.rm = TRUE)) %>% 
  select(-intj, -num, -part, -propn, -x) %>% 
  select(document, verb, noun, pron, adj, adv, adp, cconj, det, other) %>%
  rename(speaker = document) %>%
  ungroup()

# How does it look?
head(sbc_dfm)

# Recall that our data isn't normalized, as we didn't sample exactly 1000
# tokens like Brezina. So we need to normalize by row sums.
sbc_dfm <- sbc_dfm %>%  
  mutate(row_sum = rowSums(select(., 2:10))) %>% 
  mutate_at(2:10, ~ (./row_sum)*1000) %>% 
  select(-row_sum)

# How are we looking?
head(sbc_dfm)

# As a last step, we'll add the gender variable to the speaker variable
# and move the resulting column to the row names.
sbc_dfm <- sbc_dfm %>% left_join(select(sbc_sub, speaker, gender), by = "speaker") %>%
  select(gender, speaker, verb:other)%>% 
  unite("speaker", gender:speaker, sep = "_") %>%
  column_to_rownames("speaker")

# Looks good...
head(sbc_dfm)

# We're ready for the CA, just as we did before...
sbc_ca <- CA(sbc_dfm, graph = FALSE)

# Check the output...
summary(sbc_ca)

get_eigenvalue(sbc_ca)

# And finally we can generate our plot...
fviz_ca_biplot(sbc_ca, repel = TRUE)

# It looks pretty good, if not quite as clean as Brezina's example.
# Pete's production looks VERY consistent across conversations.
# The other 2 are little more spread out.

##
# Can you offer any sort of speculation as to why this might be?
# You might want to read the descriptions of the speech events here;
# https://www.linguistics.ucsb.edu/research/santa-barbara-corpus
##

# Let's finish up with some mixed-effects modeling.
# This is somewhat similar to logistic regression, as Brezina notes.
# It estimates the effects of one or more explanatory variables on a
# response variable. The output of a mixed model will give you a list 
# of explanatory values, estimates and confidence intervals of their 
#effect sizes, p-values for each effect, and at least one measure of 
# how well the model fits. But in some cases, you may have data with 
# more than one source of random variability. 
# For this exercise, we'll need the lme4 package.
library(lme4)

# We're going to replicate the example that is described on pg. 208-210.
# We'll start by reading in his data.
intensifiers_df <- read_csv("http://corpora.lancs.ac.uk/stats/data/mixed_effect_intensifiers.csv")

# We're going to want to convert character columns to factors.
intensifiers_df <- intensifiers_df %>% mutate_if(is.character, as.factor)

# Now let's peek at the data...
head(intensifiers_df)

# Our response variable ("Outcome") is a factor with only 2 levels:
# variants "very" and really". We have 4  predictor variables
# ("Gender", "Age", "Class" and "Syntax"). Those explantory variables are the 
# result of direct observation, so they are fixed effects.
# But we also have to grapple with indidual speaker preferences.
# These are random effects, sources of variation that need to be taken
# into account in the model.
#
# 
# The formula should look very familiar except for "(1|Speaker)",
# which is the syntax for specifying our random effects.
#
# And ignore the warning for now...
intensifiers_ml <- glmer(Outcome ~ Gender + Age + Class + Syntax + (1|Speaker), data=intensifiers_df,
                   family = binomial(link = "logit"))

# Examine the summary...
summary(intensifiers_ml)

##
# Compare this to pg. 209.
# How do you intrepret this result?
##

# Note that we can set nAGQ to the # of desired iterations for
# model convergence.
intensifiers_ml <- glmer(Outcome ~ Gender + Age + Class + Syntax + (1|Speaker), data=intensifiers_df,
                         family = binomial(link = "logit"), nAGQ = 25)

# This changes the result slightly...
summary(intensifiers_ml)

